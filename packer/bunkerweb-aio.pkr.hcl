packer {
  required_version = ">= 1.9.0"

  required_plugins {
    outscale = {
      version = ">= 1.1.1"
      source  = "github.com/outscale/outscale"
    }
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "access_key" {
  description = "Outscale Access Key ID"
  type        = string
  default     = env("OSC_ACCESS_KEY")
  sensitive   = true
}

variable "secret_key" {
  description = "Outscale Secret Key"
  type        = string
  default     = env("OSC_SECRET_KEY")
  sensitive   = true
}

variable "region" {
  description = "Outscale region"
  type        = string
  default     = "eu-west-2"
}

variable "vm_type" {
  description = "Type de VM pour le build"
  type        = string
  default     = "tinav5.c2r4p3"
}

variable "subnet_id" {
  description = "Subnet ID pour le build (optionnel)"
  type        = string
  default     = ""
}

variable "security_group_id" {
  description = "Security group ID pour le build (doit autoriser SSH entrant)"
  type        = string
  default     = ""
}

variable "bunkerweb_version" {
  description = "Version BunkerWeb à installer (ex: 1.6.11)"
  type        = string
  default     = "1.6.11"
}

variable "omi_name_prefix" {
  description = "Préfixe du nom de l'OMI générée"
  type        = string
  default     = "bunkerweb-aio-debian13"
}

variable "ssh_username" {
  description = "Utilisateur SSH de l'OMI source (Outscale Debian 13)"
  type        = string
  default     = "outscale"
}



# ---------------------------------------------------------------------------
# Source : OMI Debian 13 officielle Outscale
# La source OMI est recherchée dynamiquement via filtre sur le nom
# ---------------------------------------------------------------------------

source "outscale-bsu" "bunkerweb_aio" {
  access_key           = var.access_key
  secret_key           = var.secret_key
  region               = var.region
  custom_endpoint_oapi = "https://api.${var.region}.outscale.com/oapi/latest"

  # Recherche automatique de la dernière OMI Debian 13 Outscale officielle
  source_omi_filter {
    filters = {
      "name"                = "Debian-13-*"
      "virtualization-type" = "hvm"
      "architecture"        = "x86_64"
      "root-device-type"    = "ebs"
    }
    owners      = ["Outscale"]
    most_recent = true
  }

  # Instance
  vm_type = var.vm_type

  # Réseau (optionnel – commentez si vous utilisez le réseau par défaut)
  dynamic "subnet_filter" {
    for_each = var.subnet_id != "" ? [var.subnet_id] : []
    content {
      filters = {
        "subnet-id" = subnet_filter.value
      }
      most_free = true
      random    = false
    }
  }

  # Stockage racine – 20 Go gp2 suffit pour un build OMI
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_vm_deletion = true
  }

  # Connexion SSH
  ssh_username                = var.ssh_username
  ssh_timeout                 = "10m"
  ssh_clear_authorized_keys   = true
  associate_public_ip_address = true

  # OMI de sortie
  omi_name        = "${var.omi_name_prefix}-${var.bunkerweb_version}-{{timestamp}}"
  omi_description = "BunkerWeb ${var.bunkerweb_version} Full Stack (Linux natif, sans Docker) sur Debian 13"

  omi_groups = []  # privée par défaut
  omi_regions = [var.region]

  tags = {
    Name          = "${var.omi_name_prefix}-${var.bunkerweb_version}"
    BunkerWebVersion = var.bunkerweb_version
    OS            = "Debian-13"
    Builder       = "Packer"
    ManagedBy     = "Packer+Ansible"
  }
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

build {
  name    = "bunkerweb-aio-omi"
  sources = ["source.outscale-bsu.bunkerweb_aio"]

  # Attente que cloud-init ait terminé avant de lancer Ansible
  provisioner "shell" {
    inline = [
      "echo '>>> Attente de la fin de cloud-init...'",
      "cloud-init status --wait 2>/dev/null || true",
      "echo '>>> Cloud-init OK'",
    ]
  }

  # Provisionnement Ansible
  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/playbook.yml"
    user          = var.ssh_username
    use_proxy     = false

    extra_arguments = [
      "-e", "bunkerweb_version=${var.bunkerweb_version}",
      "-e", "ansible_python_interpreter=/usr/bin/python3",
      "--diff",
    ]

    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_STDOUT_CALLBACK=yaml",
    ]
  }

  # Nettoyage final avant snapshot
  provisioner "shell" {
    inline = [
      "echo '>>> Nettoyage pre-snapshot...'",
      "sudo cloud-init clean --logs",
      "sudo truncate -s0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo rm -f /root/.ssh/authorized_keys",
      "sudo rm -f /home/${var.ssh_username}/.ssh/authorized_keys 2>/dev/null || true",
      "sudo find /tmp /var/tmp -mindepth 1 -delete 2>/dev/null || true",
      "sudo journalctl --rotate && sudo journalctl --vacuum-time=1s 2>/dev/null || true",
      "sudo apt-get clean -y",
      "sudo rm -rf /var/lib/apt/lists/*",
      "echo '>>> Nettoyage terminé'",
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}

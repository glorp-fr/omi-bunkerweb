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
  type      = string
  default   = env("OSC_ACCESS_KEY")
  sensitive = true
}

variable "secret_key" {
  type      = string
  default   = env("OSC_SECRET_KEY")
  sensitive = true
}

variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "vm_type" {
  type    = string
  default = "tinav6.c2r4p2"
}

variable "omi_source" {
  description = "ID de l'OMI Debian 13 source (osc-cli api ReadImages --Filters '{\"AccountAliases\":[\"Outscale\"],\"ImageNames\":[\"Debian-13-*\"]}')"
  type        = string
}

variable "bunkerweb_version" {
  type    = string
  default = "1.6.11"
}

variable "ssh_username" {
  type    = string
  default = "outscale"
}


# ---------------------------------------------------------------------------
# Source
# ---------------------------------------------------------------------------

source "outscale-bsu" "bunkerweb_aio" {
  access_key           = var.access_key
  secret_key           = var.secret_key
  region               = var.region
  custom_endpoint_oapi = "https://api.${var.region}.outscale.com/oapi/latest"
  source_omi           = var.omi_source
  vm_type              = var.vm_type

  communicator                = "ssh"
  ssh_username                = var.ssh_username
  ssh_interface               = "public_ip"
  ssh_timeout                 = "10m"
  ssh_clear_authorized_keys   = true
  associate_public_ip_address = true

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_vm_deletion = true
  }

  omi_name        = "bunkerweb-aio-debian13-${var.bunkerweb_version}-{{timestamp}}"
  omi_description = "BunkerWeb ${var.bunkerweb_version} Full Stack sans Docker sur Debian 13"
  omi_groups      = []
  omi_regions     = [var.region]

  tags = {
    Name             = "bunkerweb-aio-debian13-${var.bunkerweb_version}"
    BunkerWebVersion = var.bunkerweb_version
    OS               = "Debian-13"
    Builder          = "Packer"
  }
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

build {
  name    = "bunkerweb-aio"
  sources = ["source.outscale-bsu.bunkerweb_aio"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait 2>/dev/null || true",
    ]
  }

  provisioner "ansible" {
    playbook_file = "${path.root}/playbook.yml"
    user          = var.ssh_username
    use_proxy     = false
    extra_arguments = [
      "-e", "bunkerweb_version=${var.bunkerweb_version}",
      "-e", "ansible_python_interpreter=/usr/bin/python3",
    ]
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_STDOUT_CALLBACK=yaml",
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo cloud-init clean --logs",
      "sudo truncate -s0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo apt-get clean -y",
      "sudo rm -rf /var/lib/apt/lists/*",
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}

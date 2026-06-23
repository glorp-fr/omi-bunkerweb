# OMI BunkerWeb AIO – Outscale

Build d'une OMI Outscale avec **BunkerWeb Full Stack** installé nativement (sans Docker) sur **Debian 13 (Trixie)**.

BunkerWeb est un WAF open-source basé sur NGINX avec ModSecurity, CRS OWASP, et une Web UI intégrée.

## Architecture

- **nginx** (root) gère les ports 80/443
- **bunkerweb-ui** (gunicorn, user nginx) écoute sur `127.0.0.1:7000`
- **bunkerweb-scheduler** orchestre la configuration et redémarre nginx si besoin
- Le filtrage réseau est géré par les **security groups Outscale** (pas de firewall OS)

## Prérequis

| Outil | Version min |
|-------|-------------|
| Packer | ≥ 1.9.0 |
| Plugin Packer `outscale/outscale` | ≥ 1.1.1 |
| Plugin Packer `hashicorp/ansible` | ≥ 1.1.1 |
| Ansible | ≥ 2.14 |
| `osc-cli` | pour trouver l'OMI source Debian 13 |

## Structure

```
omi-bunkerweb/
├── bunkerweb-aio.pkr.hcl              # Template Packer
├── bunkerweb-aio.pkrvars.hcl.example  # Exemple de variables (à copier)
├── playbook.yml                        # Playbook Ansible (MAJ OS + BunkerWeb)
├── Makefile                            # Raccourcis de commandes
└── README.md
```

## Démarrage rapide

### 1. Cloner le repo

```bash
git clone https://github.com/glorp-fr/omi-bunkerweb.git
cd omi-bunkerweb
```

### 2. Trouver l'OMI Debian 13 source

```bash
osc-cli api ReadImages \
  --Filters '{"AccountAliases":["Outscale"],"ImageNames":["Debian-13-*"],"Architectures":["x86_64"]}' \
  | grep -E '"ImageId"|"ImageName"'
```

Exemple de résultat :
```
"ImageId": "ami-29671c1b",
"ImageName": "Debian-13-2026-04-14",
```

### 3. Configurer les variables

```bash
cp bunkerweb-aio.pkrvars.hcl.example bunkerweb-aio.pkrvars.hcl
vi bunkerweb-aio.pkrvars.hcl
```

Renseigner :

```hcl
access_key        = "VOTRE_ACCESS_KEY"
secret_key        = "VOTRE_SECRET_KEY"
region            = "cloudgouv-eu-west-1"   # ou eu-west-2
vm_type           = "tinav6.c2r4p2"
bunkerweb_version = "1.6.11"
omi_source        = "ami-29671c1b"           # OMI Debian 13 trouvée à l'étape 2
```

> ⚠️ Ne jamais commiter `bunkerweb-aio.pkrvars.hcl` — il est dans le `.gitignore`.

### 4. Initialiser les plugins Packer

```bash
make init
```

### 5. Lancer le build

```bash
make build
```

Le build dure environ **15–20 minutes**. À la fin, l'OMI est disponible dans ton compte Outscale sous le nom `bunkerweb-aio-debian13-1.6.11-<timestamp>`.

## Ce que fait le build

Le build Packer lance une VM temporaire depuis l'OMI Debian 13 source, puis Ansible :

1. **Met à jour l'OS** (`dist-upgrade`)
2. **Installe les paquets** : curl, gnupg2, chrony, python3
3. **Durcit SSH** : `PasswordAuthentication no`, `PermitRootLogin no`
4. **Installe BunkerWeb Full Stack** via `install-bunkerweb.sh` officiel :
   - `bunkerweb` (nginx + ModSecurity WAF) → ports 80/443
   - `bunkerweb-scheduler` (orchestration de la configuration)
   - `bunkerweb-ui` (interface Web gunicorn) → `127.0.0.1:7000`
5. **Déploie un script `first-boot`** exécuté au premier démarrage de l'instance
6. **Nettoie** l'image avant snapshot (cloud-init, machine-id, caches apt)

> Le filtrage réseau est délégué aux **security groups Outscale** — aucun firewall OS n'est installé.

## Utilisation de l'OMI

### Démarrer une instance

Créez une instance depuis l'OMI générée avec un security group autorisant au minimum les ports **22** (SSH) et **7000** (Web UI).

### Sans user-data

Au premier démarrage, BunkerWeb démarre avec sa configuration par défaut et affiche le **wizard de première connexion** sur :

```
http://<IP>:7000/
```

Le wizard permet de créer le compte administrateur et de configurer BunkerWeb interactivement.

### Avec user-data

Passez la configuration en **user-data** (format `KEY=VALUE`, une variable par ligne) pour bypasser le wizard :

```
BW_ADMIN_USERNAME=admin
BW_ADMIN_PASSWORD=MonMotDePasse!1
BW_SERVER_NAME=www.monsite.fr
BW_REVERSE_PROXY_HOST=http://127.0.0.1:8000
BW_AUTO_LETSENCRYPT=yes
BW_EMAIL_LETSENCRYPT=admin@monsite.fr
```

Au premier démarrage, le service `bunkerweb-first-boot` lit ces variables depuis les métadonnées IMDS Outscale (`169.254.169.254`) et configure BunkerWeb avant de démarrer les services.

### Variables user-data disponibles

| Variable | Description |
|----------|-------------|
| `BW_ADMIN_USERNAME` | Identifiant admin UI (défaut: `admin`) |
| `BW_ADMIN_PASSWORD` | Mot de passe admin UI — si absent, le wizard s'affiche |
| `BW_SERVER_NAME` | FQDN du site à protéger |
| `BW_REVERSE_PROXY_HOST` | Upstream backend (ex: `http://127.0.0.1:8000`) |
| `BW_AUTO_LETSENCRYPT` | `yes` pour activer Let's Encrypt |
| `BW_EMAIL_LETSENCRYPT` | Email pour Let's Encrypt |

### Accès à la Web UI

| Cas | URL |
|-----|-----|
| Sans user-data | `http://<IP>:7000/` → wizard de première connexion |
| Avec `BW_ADMIN_PASSWORD` | `http://<IP>:7000/` → connexion directe |
| Avec `BW_SERVER_NAME` configuré | `http://<IP>/` via BunkerWeb (nginx) |

### Logs

```bash
# Log du first-boot
cat /var/log/bunkerweb/first-boot.log

# Logs des services
journalctl -u bunkerweb -f
journalctl -u bunkerweb-scheduler -f
journalctl -u bunkerweb-ui -f
```

## Commandes Makefile

```bash
make init      # Télécharger les plugins Packer
make validate  # Valider le template
make build     # Lancer le build de l'OMI
make clean     # Nettoyer les fichiers temporaires
```

Surcharger la version ou la région :

```bash
make build BW_VERSION=1.6.11 REGION=cloudgouv-eu-west-1
```

## Variables Packer

| Variable | Défaut | Description |
|----------|--------|-------------|
| `access_key` | `$OSC_ACCESS_KEY` | Clé d'accès Outscale |
| `secret_key` | `$OSC_SECRET_KEY` | Clé secrète Outscale |
| `region` | `eu-west-2` | Région Outscale |
| `vm_type` | `tinav6.c2r4p2` | Type de VM pour le build |
| `omi_source` | — | ID de l'OMI Debian 13 source (**obligatoire**) |
| `bunkerweb_version` | `1.6.11` | Version BunkerWeb à installer |

Les credentials peuvent aussi être passés via variables d'environnement :

```bash
export OSC_ACCESS_KEY="xxxxxxxxxxxx"
export OSC_SECRET_KEY="xxxxxxxxxxxx"
make build-clean
```

## Références

- [BunkerWeb – Documentation](https://docs.bunkerweb.io/latest/)
- [BunkerWeb – Linux Integration](https://docs.bunkerweb.io/latest/integrations/#linux)
- [Plugin Packer Outscale](https://github.com/outscale/packer-plugin-outscale)
- [API OAPI Outscale](https://docs.outscale.com/api)

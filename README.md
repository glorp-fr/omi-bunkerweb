# OMI BunkerWeb AIO – Outscale (Packer + Ansible)

Build d'une OMI Outscale prête à l'emploi avec **BunkerWeb Full Stack** installé nativement (sans Docker) sur **Debian 13 (Trixie)**.

## Architecture

```
packer-bunkerweb-omi/
├── packer/
│   ├── bunkerweb-aio.pkr.hcl           # Template Packer principal
│   └── bunkerweb-aio.pkrvars.hcl.example
├── ansible/
│   ├── ansible.cfg
│   ├── playbook.yml
│   └── roles/
│       ├── os_hardening/               # MAJ OS + UFW + fail2ban + sysctl
│       │   ├── tasks/main.yml
│       │   └── handlers/main.yml
│       └── bunkerweb/                  # Installation BunkerWeb Full Stack
│           ├── tasks/main.yml
│           ├── handlers/main.yml
│           └── templates/
│               ├── variables.env.j2
│               ├── scheduler.env.j2
│               ├── ui.env.j2
│               └── bunkerweb-first-boot.sh.j2
└── Makefile
```

## Ce que fait l'OMI

- **Mise à jour complète** Debian 13 (dist-upgrade)
- **Durcissement OS** : UFW (ports 22/80/443), fail2ban SSH, sysctl réseau
- **BunkerWeb Full Stack** installé via `install-bunkerweb.sh` officiel :
  - `bunkerweb` (nginx + ModSecurity + WAF)
  - `bunkerweb-scheduler` (cerveau de la configuration)
  - `bunkerweb-ui` (interface Web sur `127.0.0.1:7000`)
- **Services systemd** activés, démarrés au premier boot
- **Script `bunkerweb-first-boot.sh`** exécuté une seule fois au démarrage de l'instance pour appliquer la configuration via user-data

> **Note** : "AIO" désigne ici l'installation Full Stack Linux native (équivalent fonctionnel du container `bunkerweb-all-in-one`, sans Docker).

## Prérequis

| Outil | Version min |
|-------|-------------|
| Packer | ≥ 1.9.0 |
| Plugin `outscale/outscale` | ≥ 1.1.1 |
| Plugin `hashicorp/ansible` | ≥ 1.1.1 |
| Ansible | ≥ 2.14 |
| Accès réseau vers GitHub (téléchargement du script BunkerWeb) | — |

## Démarrage rapide

### 1. Configurer les credentials

```bash
cp packer/bunkerweb-aio.pkrvars.hcl.example packer/bunkerweb-aio.pkrvars.hcl
# Éditez avec vos clés Outscale
vi packer/bunkerweb-aio.pkrvars.hcl
```

Ou via variables d'environnement :

```bash
export OSC_ACCESS_KEY="xxxxxxxxxxxx"
export OSC_SECRET_KEY="xxxxxxxxxxxx"
```

### 2. Initialiser les plugins Packer

```bash
make init
```

### 3. Valider le template

```bash
make validate
```

### 4. Lancer le build

```bash
make build
# ou avec une version spécifique
make build BW_VERSION=1.6.11
```

Le build crée une OMI nommée `bunkerweb-aio-debian13-1.6.11-<timestamp>` dans la région configurée.

## Configuration de l'instance au démarrage

Passez les variables suivantes en **user-data** de votre instance Outscale :

```
BW_SERVER_NAME=www.monsite.fr
BW_REVERSE_PROXY_HOST=http://127.0.0.1:8000
BW_ADMIN_USERNAME=admin
BW_ADMIN_PASSWORD=MonMotDePasseSécurisé!
BW_AUTO_LETSENCRYPT=yes
BW_EMAIL_LETSENCRYPT=admin@monsite.fr
```

Le script `/usr/local/sbin/bunkerweb-first-boot.sh` s'exécute au premier démarrage, lit ces variables depuis les métadonnées IMDS Outscale et configure BunkerWeb avant de démarrer les services.

## Accès à la Web UI

La Web UI écoute sur `127.0.0.1:7000`. Elle est exposée via BunkerWeb lui-même en reverse proxy.

Après démarrage, accédez à `http://<IP_INSTANCE>/bwadmin` (ou le chemin défini dans `variables.env`).

## Ports ouverts par UFW

| Port | Protocole | Usage |
|------|-----------|-------|
| 22 | TCP | SSH |
| 80 | TCP | HTTP (BunkerWeb) |
| 443 | TCP | HTTPS (BunkerWeb) |
| 443 | UDP | QUIC/HTTP3 (BunkerWeb) |

## Personnalisation du build

| Variable Packer | Défaut | Description |
|----------------|--------|-------------|
| `bunkerweb_version` | `1.6.11` | Version BunkerWeb à installer |
| `vm_type` | `tinav5.c2r4p3` | Type de VM pour le build |
| `region` | `eu-west-2` | Région Outscale |
| `omi_name_prefix` | `bunkerweb-aio-debian13` | Préfixe du nom OMI |

Variables Ansible (surchargeables via `-e`) :

| Variable | Défaut | Description |
|----------|--------|-------------|
| `bunkerweb_ui_enabled` | `true` | Activer la Web UI |
| `bunkerweb_api_enabled` | `false` | Activer l'API FastAPI |
| `bunkerweb_crowdsec` | `false` | Intégrer CrowdSec |

## Mise à jour de BunkerWeb sur une instance existante

```bash
sudo /tmp/install-bunkerweb.sh --version 1.6.12 -y
```

## Références

- [BunkerWeb – Linux Integration](https://docs.bunkerweb.io/latest/integrations/#linux)
- [install-bunkerweb.sh – GitHub Releases](https://github.com/bunkerity/bunkerweb/releases)
- [Plugin Packer Outscale](https://github.com/outscale/packer-plugin-outscale)
- [API OAPI Outscale](https://docs.outscale.com/api)

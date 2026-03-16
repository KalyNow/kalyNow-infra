# kalyNow-infra

Infrastructure kalyNow basée sur **Nomad + Consul + Vault + Traefik**.  
Supporte deux environnements : **`local`** (dev) et **`prod`** (production).

---

## Structure du dépôt

```
kalyNow-infra/
├── Makefile                        # Commandes raccourcies (make deploy, make restart…)
├── scripts/
│   ├── deploy.sh                   # Script de déploiement ordonné (local | prod)
│   ├── generate_vars.py            # Génère les .vars Nomad depuis config.py
│   ├── bootstrap_vault.py          # Init / unseal / bootstrap Vault
│   ├── config.example.py           # Template de configuration (source de vérité)
│   ├── config.py                   # Config locale remplie (⚠️ ne pas committer)
│   └── setup_nomad_volumes.sh      # Création des volumes hôtes
├── nomad/
│   ├── config/
│   │   ├── nomad.hcl               # Config agent Nomad
│   │   └── volumes.hcl             # Déclaration volumes hôtes
│   └── jobs/                       # Fichiers de job Nomad (partagés entre envs)
│       ├── consul.nomad.hcl
│       ├── vault.nomad.hcl
│       ├── traefik.nomad.hcl
│       ├── postgres.nomad.hcl
│       ├── mongodb.nomad.hcl
│       ├── rustfs.nomad.hcl
│       ├── user-service.nomad.hcl
│       ├── offer-service.nomad.hcl
│       └── web.nomad.hcl
├── environments/
│   ├── local/
│   │   └── jobs/                   # Variables overrides — dev local
│   │       ├── consul.vars
│   │       ├── vault.vars
│   │       ├── traefik.vars
│   │       ├── postgres.vars
│   │       ├── mongodb.vars
│   │       ├── rustfs.vars
│   │       ├── user-service.vars
│   │       ├── offer-service.vars
│   │       └── web.vars
│   └── prod/
│       └── jobs/                   # Variables overrides — production
│           ├── consul.vars
│           ├── vault.vars
│           ├── traefik.vars
│           ├── postgres.vars
│           ├── mongodb.vars
│           ├── rustfs.vars
│           ├── user-service.vars
│           ├── offer-service.vars
│           └── web.vars
└── config/
    ├── clickhouse/
    ├── redis/
    └── vault/
```

> **Principe** : les fichiers `nomad/jobs/*.nomad.hcl` sont partagés entre les deux environnements.
> Les fichiers `environments/<env>/jobs/*.vars` sont **générés automatiquement** par `generate_vars.py`
> depuis `scripts/config.py` — ne pas les éditer manuellement.

---

## Services gérés dans ce repo

| Service | Description | Port local | Port preprod/prod |
|---------|-------------|-----------|-------------------|
| Consul | Service discovery | 8500 | 8500 |
| Vault | Secrets manager | 8200 | 8200 |
| Traefik | Reverse proxy / ingress | :80, :8080 | :8888, :8080 |
| PostgreSQL | DB relationnelle | 5432 | 5433 (évite conflit) |
| MongoDB | DB documentaire | 27017 | 27017 |
| RustFS | Stockage S3-compatible | 9000, 9001 | 9000, 9001 |
| user-service | API utilisateurs | dynamic | dynamic |
| offer-service | API offres/restaurants | dynamic | dynamic |
| web | Frontend React/Vite | dynamic | dynamic |

---

## Prérequis

| Outil | Usage |
|-------|-------|
| Docker Engine | Runtime des containers |
| `nomad` CLI + agent | Orchestrateur |
| `consul` CLI (optionnel) | Debug service discovery |
| `python3` | Bootstrap Vault |
| `make` | Raccourcis commandes |

### Installation Nomad

```bash
curl -LO https://releases.hashicorp.com/nomad/1.11.3/nomad_1.11.3_linux_amd64.zip
unzip nomad_1.11.3_linux_amd64.zip
sudo install nomad /usr/local/bin/nomad
nomad version
```

---

## 1) Configuration Nomad

> ⚠️ Ne jamais éditer directement `/etc/nomad.d/`. Toujours modifier `nomad/config/` puis copier.

| Fichier repo | Destination système |
|---|---|
| `nomad/config/nomad.hcl` | `/etc/nomad.d/nomad.hcl` |
| `nomad/config/volumes.hcl` | `/etc/nomad.d/volumes.hcl` |

```bash
sudo mkdir -p /etc/nomad.d
sudo cp nomad/config/nomad.hcl  /etc/nomad.d/nomad.hcl
sudo cp nomad/config/volumes.hcl /etc/nomad.d/volumes.hcl
```

### Volumes hôtes (une seule fois)

```bash
sudo mkdir -p /opt/nomad/volumes/{postgres,mongodb,rustfs}
# ou via le script fourni :
bash scripts/setup_nomad_volumes.sh
```

### Lancer l'agent Nomad

```bash
sudo mkdir -p /nomad/data
nomad agent -config=/etc/nomad.d
```

Dans un autre terminal :

```bash
export NOMAD_ADDR=http://127.0.0.1:4646
```

---

## 2) Environnement local (dev)

### Hostnames locaux

Ajouter dans `/etc/hosts` :

```
127.0.0.1  kalynow.mg  traefik.kalynow.mg  vault.kalynow.mg
```

### Premier démarrage — Configuration

`config.py` est la **source de vérité unique** pour toute l'infrastructure :

```bash
cp scripts/config.example.py scripts/config.py
# Remplir scripts/config.py
```

Ce fichier contrôle **deux choses à la fois** :

| Ce que `config.py` pilote | Via quel script |
|---|---|
| Secrets applicatifs (DB URL, JWT, credentials…) | `bootstrap_vault.py` → écrit dans Vault |
| Variables Nomad (ports, images, ressources…) | `generate_vars.py` → écrit les `.vars` |

Exemple : changer `POSTGRES_PORT = "5433"` dans `config.py` met à jour **en même temps** :
- Le port hôte du container Postgres Nomad
- La `DATABASE_URL` injectée dans user-service via Vault

> Tout le reste (init Vault, génération des vars, unseal, déploiement) est **géré automatiquement** par `make deploy`.

### Déploiement local

**Tout déployer d'un coup (recommandé) :**

```bash
make deploy ENV=local
# ou : bash scripts/deploy.sh local
```

**Redémarrer tous les jobs (sauf Consul) :**

```bash
make restart ENV=local
# Arrête tout sauf consul → attend que Vault soit prêt → redéploie dans l'ordre
```

**Déployer un seul job :**

```bash
make job JOB=web ENV=local
make job JOB=offer-service ENV=local
```

**Valider un job sans le déployer :**

```bash
make plan JOB=traefik ENV=local
```

**Valider tous les jobs :**

```bash
make lint ENV=local
```

### Ordre de déploiement

```
consul → vault → [Vault gate: init/unseal] → traefik → postgres → mongodb → rustfs → user-service → offer-service → web
```

### Variables locales

Les overrides sont dans `environments/local/jobs/<job>.vars`.
Valeurs typiques : image tag `:local`, `force_pull = false`, ressources minimales, `count = 1`.

### URLs utiles en dev

| Service | URL |
|---------|-----|
| Nomad UI | http://127.0.0.1:4646 |
| Consul UI | http://127.0.0.1:8500 |
| Vault UI | http://127.0.0.1:8200/ui |
| Traefik Dashboard | http://traefik.kalynow.mg:8080 |
| Frontend web | http://kalynow.mg |
| User Service Swagger | http://kalynow.mg/api/us/ |
| Offer Service Swagger | http://kalynow.mg/api/of/ |

---

## 3) Environnement production / preprod

### Prérequis serveur

- Nomad agent configuré et démarré
- Docker Engine installé
- DNS pointant `kalynow.mg` et sous-domaines vers le serveur
- `NOMAD_ADDR` exporté (ou configuré dans `~/.nomad`)

### Configuration prod dans `config.py`

Tout se configure dans `scripts/config.py`. Les valeurs à adapter pour un serveur prod/preprod :

```python
# ── Domaine ──────────────────────────────────────────────────────────────────
DOMAIN     = "kalynow.mg"
FORCE_PULL = True

# ── Traefik ───────────────────────────────────────────────────────────────────
TRAEFIK_HTTP_PORT         = 8888   # derrière nginx sur le serveur
TRAEFIK_DASHBOARD_ENABLED = False

# ── PostgreSQL ───────────────────────────────────────────────────────────────────
POSTGRES_PORT = "5433"   # évite le conflit avec le Postgres existant sur 5432
                          # → aussi utilisé dans DATABASE_URL envoyée à user-service

# ── Images (taguées par le pipeline CI/CD) ───────────────────────────────────
USER_SERVICE_IMAGE  = "kalynow/user-service:latest"
OFFER_SERVICE_IMAGE = "kalynow/offer-service:latest"
WEB_IMAGE           = "kalynow/web:latest"

# ── Ressources ─────────────────────────────────────────────────────────────────
USER_SERVICE_COUNT  = 2
OFFER_SERVICE_COUNT = 2
WEB_COUNT           = 2
```

Une fois `config.py` rempli, `make deploy` fait tout le reste.

### Déploiement

```bash
export NOMAD_ADDR=http://<server-ip>:4646

make deploy ENV=prod
# 1. génère environments/prod/jobs/*.vars depuis config.py
# 2. bootstrap Vault (init/unseal si nécessaire)
# 3. déploie tous les jobs dans l'ordre
```

**Redémarrer un seul job :**

```bash
make job JOB=offer-service ENV=prod
```

**Redémarrer tous les jobs (sauf consul) :**

```bash
make restart ENV=prod
```

### Architecture réseau preprod

Sur le serveur preprod, nginx tourne déjà sur :80/:443 — Traefik tourne sur :8888 :

```
nginx :80/:443  →  Traefik :8888  →  services (ports dynamiques Nomad)
```

Traefik lit les routes depuis Consul et route automatiquement les requêtes.

---

## 4) Commandes Make — référence complète

```bash
make help                              # Afficher toutes les commandes

make deploy   ENV=local|prod           # Déployer tous les jobs dans l'ordre
make restart  ENV=local|prod           # Arrêter tout (sauf consul) puis redéployer
make job      ENV=local|prod  JOB=<n>  # Déployer un seul job
make plan     ENV=local|prod  JOB=<n>  # Dry-run (plan) d'un job
make lint     ENV=local|prod           # Valider tous les fichiers de job

make stop     JOB=<name>               # Arrêter un job
make stop-all                          # Arrêter les services applicatifs

make status                            # État de tous les jobs
make logs     JOB=<name>               # Tail des logs d'un job

make vault-unseal                      # Dévérouiller Vault après un redémarrage
make vault-init                        # Initialiser Vault (première fois uniquement)
make vault-bootstrap                   # Bootstrapper les secrets Vault
```

---

## 5) Commandes Nomad utiles

```bash
# État général
nomad job status

# État d'un job spécifique
nomad job status traefik
nomad job status user-service

# Logs d'une allocation
nomad alloc logs -f $(nomad job allocs -latest web | tail -1 | awk '{print $1}') web

# Routeurs Traefik chargés
curl -s http://127.0.0.1:8080/api/http/routers | jq -r '.[].name'
```

---

## Notes importantes

- **`scripts/config.py`** est la **source de vérité unique** — ports, images, credentials, ressources. Ne jamais éditer les `.vars` manuellement.
- **`scripts/.vault-init.json`** contient les clés unseal et le root token → **ne jamais committer ce fichier** (il est dans `.gitignore`).
- **`scripts/config.py`** contient des credentials → **ne jamais committer ce fichier**.
- Les fichiers `environments/*/jobs/*.vars` sont **générés** par `generate_vars.py` — ils peuvent être regénérés à tout moment.
- Vault tourne en mode **file storage** — les secrets survivent aux redémarrages du container mais pas à la suppression du volume.
- Traefik lit les routes depuis Consul (`consulCatalog`) via les tags des jobs Nomad — Consul doit toujours être up.
- Les fichiers `.nomad.hcl` sont **identiques entre local et prod** ; seuls les `.vars` diffèrent (et sont générés).

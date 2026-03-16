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
│   ├── bootstrap_vault.py          # Init / unseal / bootstrap Vault
│   ├── config.example.py           # Template de configuration Vault
│   ├── config.py                   # Config locale (⚠️ ne pas committer)
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
> Les différences (image tag, CPU, mémoire, domaine…) sont portées par les fichiers `.vars` dans `environments/<env>/jobs/`.

---

## Services gérés dans ce repo

| Service | Description | Port local | Port prod |
|---------|-------------|-----------|-----------|
| Consul | Service discovery | 8500 | 8500 |
| Vault | Secrets manager | 8200 | 8200 |
| Traefik | Reverse proxy / ingress | 80, 8080 | 80, 443, 8080 |
| PostgreSQL | DB relationnelle | 5432 | 5432 |
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

### Premier démarrage — Bootstrap Vault

La **seule action manuelle requise** est de remplir le fichier de configuration :

```bash
cp scripts/config.example.py scripts/config.py
# Remplir les credentials dans scripts/config.py
```

> Le reste (init Vault, écriture des secrets, unseal) est **géré automatiquement** par `make deploy` :
> - Vault non initialisé → init + bootstrap des secrets lancés automatiquement
> - Vault sealed (après reboot) → unseal automatique
> - Vault déjà prêt → rien à faire, le déploiement continue

Les clés unseal et le root token sont sauvegardés dans `scripts/.vault-init.json` → **à conserver en lieu sûr**.

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

## 3) Environnement production (prod)

### Prérequis serveur

- Nomad agent configuré et démarré
- Docker Engine installé
- DNS pointant `kalynow.mg` et sous-domaines vers le serveur
- `NOMAD_ADDR` et `NOMAD_TOKEN` exportés (ou configurés dans `~/.nomad`)

### Variables de production

Les overrides sont dans `environments/prod/jobs/<job>.vars`.
Valeurs typiques : image tag `:latest`, `force_pull = true`, ressources doublées, `count = 2` pour les services stateless.

Exemple — modifier l'image web en prod :

```hcl
# environments/prod/jobs/web.vars
web_image   = "registry.example.com/kalynow/web:v1.2.3"
web_count   = 2
web_cpu     = 200
web_memory  = 128
```

### Déploiement production

```bash
export NOMAD_ADDR=http://<server-ip>:4646
export NOMAD_TOKEN=<token>

make deploy ENV=prod
```

**Redémarrer un seul job en prod :**

```bash
make job JOB=offer-service ENV=prod
```

**Redémarrer tous les jobs en prod :**

```bash
make restart ENV=prod
```

### Traefik TLS (prod)

Traefik expose l'entrypoint `websecure` sur le port 443.
Configurer Let's Encrypt dans `nomad/jobs/traefik.nomad.hcl` pour les certificats automatiques.

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

- **`scripts/.vault-init.json`** contient les clés unseal et le root token → **ne jamais committer ce fichier** (il est dans `.gitignore`).
- **`scripts/config.py`** contient des credentials → **ne jamais committer ce fichier**.
- Vault tourne en mode **file storage** — les secrets survivent aux redémarrages du container mais pas à la suppression du volume.
- Traefik lit les routes depuis Consul (`consulCatalog`) via les tags des jobs Nomad — Consul doit toujours être up.
- Les fichiers `.nomad.hcl` sont **identiques entre local et prod** ; seuls les `.vars` diffèrent.

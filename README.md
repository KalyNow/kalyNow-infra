# kalyNow-infra

Infrastructure kalyNow — **Nomad + Consul + Vault + Traefik**.

---

## Environnements

| | Local (dev) | Production |
|---|---|---|
| Nomad | single-node, no TLS | multi-node, TLS+ACL |
| Consul | type=system (tous les nœuds) | idem |
| Vault | file storage, HTTP | file storage, HTTP (derrière TLS Nomad) |
| Config Nomad | `nomad/config/nomad.hcl` | `nomad/config/server.hcl` + `client.hcl` |
| Setup nœud | `nomad agent -config=nomad/config/nomad.hcl` | `make setup-node IP=... [VAULT_NODE=true\|SERVER_IP=...]` |

---

## Services

| Service | Port local | Port prod | Notes |
|---------|-----------|-----------|-------|
| Consul | 8500 | 8500 | service discovery |
| Vault | 8200 | 8200 | secrets manager |
| Traefik | :80, :8080 | :8888, :8080 | reverse proxy |
| PostgreSQL | 5432 | 5433 | 5433 en prod (5432 pris par le postgres natif) |
| MongoDB | 27017 | 27017 | |
| RustFS | 9000, 9001 | 9000, 9001 | S3-compatible |
| user-service | dynamique | dynamique | |
| offer-service | dynamique | dynamique | |
| web | dynamique | dynamique | React/Vite |

---

## Prérequis

- Docker Engine
- `nomad` ≥ 1.11
- `python3`
- `make`

```bash
# Installer Nomad
curl -LO https://releases.hashicorp.com/nomad/1.11.3/nomad_1.11.3_linux_amd64.zip
unzip nomad_1.11.3_linux_amd64.zip && sudo install nomad /usr/local/bin/nomad
```

---

## Développement local

### 1. Démarrer Nomad

```bash
sudo nomad agent -config=nomad/config/nomad.hcl
```

### 2. Configurer

```bash
cp scripts/config.example.py scripts/config.py
# Remplir scripts/config.py avec les credentials locaux
```

`config.py` est la **source de vérité unique** — il pilote à la fois les secrets Vault et les variables Nomad.

### 3. Déployer

```bash
make deploy ENV=local
```

Ce que fait `make deploy` :
1. Génère `environments/local/jobs/*.vars` depuis `config.py`
2. Déploie dans l'ordre : `consul → vault → traefik → postgres → mongodb → rustfs → user-service → offer-service → web`
3. Gère automatiquement l'init/unseal Vault au premier démarrage

### Hostnames locaux

Ajouter dans `/etc/hosts` :
```
127.0.0.1  kalynow.mg  traefik.kalynow.mg  vault.kalynow.mg
```

### URLs utiles

| Service | URL |
|---------|-----|
| Nomad UI | http://127.0.0.1:4646 |
| Consul UI | http://127.0.0.1:8500 |
| Vault UI | http://127.0.0.1:8200/ui |
| Traefik | http://traefik.kalynow.mg:8080 |
| Web | http://kalynow.mg |

---

## Production (multi-nœuds)

### Architecture

```
node-server  (server + client)  →  Vault, Consul, Traefik, Postgres, MongoDB, RustFS
node-client  (client only)      →  user-service, offer-service, web
```

- **Consul** : `type = "system"` → tourne automatiquement sur tous les nœuds
- **Vault** : épinglé sur node-server via `constraint { meta.vault_server = "true" }`

### Fichiers de config Nomad par environnement

| Fichier repo | Nœud cible | Déployé dans |
|---|---|---|
| `nomad/config/nomad.hcl` | local uniquement | utilisé directement |
| `nomad/config/vault.hcl` | tous les nœuds prod | `/etc/nomad.d/vault.hcl` |
| `nomad/config/volumes.hcl` | tous les nœuds prod | `/etc/nomad.d/volumes.hcl` |
| `nomad/config/server.hcl` | node-server | `/etc/nomad.d/server.hcl` |
| `nomad/config/client.hcl` | node-client | `/etc/nomad.d/client.hcl` |

### 1. Initialiser chaque nœud (une seule fois)

```bash
# Sur node-server (héberge Vault) :
make setup-node IP=<IP_de_ce_noeud> VAULT_NODE=true

# Sur node-client :
make setup-node IP=<IP_de_ce_noeud> SERVER_IP=<IP_de_node_server>
```

Le script copie les configs dans `/etc/nomad.d/`, injecte les IPs et crée les volumes.

```bash
# Redémarrer Nomad après setup :
sudo systemctl restart nomad
```

### 2. Vérifier le cluster

```bash
nomad node status    # les deux nœuds doivent être "ready"
consul members       # les deux nœuds doivent être "alive"
```

### 3. Configurer et déployer

```bash
cp scripts/config.example.py scripts/config.py
# Remplir config.py (passwords, domaine, images, ports…)

make deploy ENV=prod
```

### Volumes créés sur chaque nœud

| Volume | Chemin | Owner |
|--------|--------|-------|
| `postgres_data` | `/opt/nomad/volumes/postgres` | `root:root` |
| `mongo_data` | `/opt/nomad/volumes/mongodb` | `root:root` |
| `rustfs_data` | `/opt/nomad/volumes/rustfs` | `10001:10001` |
| `vault_data` | `/opt/nomad/volumes/vault` | `100:100` |

> ⚠️ Les jobs avec `volume { type = "host" }` ne peuvent scheduler que sur les nœuds ayant déclaré le volume dans `volumes.hcl`.

### Architecture réseau

```
nginx :80/:443  →  Traefik :8888  →  services (ports dynamiques Nomad)
```

---

## Commandes Make

```bash
make deploy   ENV=local|prod           # Déployer tous les jobs dans l'ordre
make restart  ENV=local|prod           # Arrêter tout (sauf consul) puis redéployer
make job      ENV=local|prod JOB=<n>   # Déployer un seul job
make plan     ENV=local|prod JOB=<n>   # Dry-run
make lint     ENV=local|prod           # Valider tous les fichiers de job

make stop     JOB=<name>               # Arrêter un job
make stop-all                          # Arrêter les services applicatifs
make status                            # État de tous les jobs
make logs     JOB=<name>               # Tail des logs

make vault-unseal                      # Unseal Vault après un redémarrage
make vault-init                        # Initialiser Vault (première fois)
make vault-bootstrap                   # Bootstrapper les secrets

make setup-node IP=<ip> VAULT_NODE=true             # Initialiser node-server
make setup-node IP=<ip> SERVER_IP=<server-ip>       # Initialiser node-client
```

---

## Commandes Nomad utiles

```bash
nomad job status
nomad job status <job>
nomad alloc logs -f $(nomad job allocs -latest <job> | tail -1 | awk '{print $1}') <job>
```

---

## Notes

- **`scripts/config.py`** — credentials + ports + images. **Ne jamais committer.**
- **`scripts/.vault-init.json`** — clés unseal + root token. **Ne jamais committer.**
- Les `.vars` dans `environments/*/jobs/` sont **générés** par `generate_vars.py` — ne pas éditer manuellement.
- Vault démarre **scellé** après chaque redémarrage → `make vault-unseal` ou `make deploy` le gère automatiquement.
- Les fichiers `.nomad.hcl` sont **identiques entre local et prod** — seuls les `.vars` diffèrent.
- Pour les services applicatifs (contraintes d'env vars, port binding, healthcheck…) : voir [`docs/onboarding-services.md`](docs/onboarding-services.md).

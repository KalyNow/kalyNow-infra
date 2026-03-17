# kalyNow-infra

Infrastructure kalyNow — **Nomad + Consul + Vault + Traefik**.

---

## Services

| Service | Port local | Notes |
|---------|-----------|-------|
| Consul | 8500 | service discovery |
| Vault | 8200 | secrets manager |
| Traefik | :80, :8080 | reverse proxy |
| PostgreSQL | 5432 | |
| MongoDB | 27017 | |
| RustFS | 9000, 9001 | S3-compatible |
| user-service | dynamique | |
| offer-service | dynamique | |
| web | dynamique | React/Vite |

---

## Prérequis (développement local)

- **Docker Engine**
- **`nomad`** ≥ 1.11
- **`python3`**
- **`make`**

```bash
# Installer Nomad (Linux amd64)
curl -LO https://releases.hashicorp.com/nomad/1.11.3/nomad_1.11.3_linux_amd64.zip
unzip nomad_1.11.3_linux_amd64.zip && sudo install nomad /usr/local/bin/nomad
```

> Pour le déploiement sur serveur (multi-nœuds), voir [docs/server-deployment.md](docs/server-deployment.md).

---

## Développement local (single-node)

### 1. Démarrer Nomad

```bash
sudo nomad agent -config=nomad/config/nomad.hcl
```

Nomad démarre en mode **single-node** (server + client sur la même machine), sans TLS ni ACL.

### 2. Configurer

```bash
cp scripts/config.example.py scripts/config.py
# Remplir scripts/config.py avec vos credentials locaux
```

`config.py` est la **source de vérité unique** — il pilote à la fois les secrets Vault et les variables Nomad.

### 3. Déployer

```bash
make deploy ENV=local
```

Ce que fait `make deploy` :

1. Génère `environments/local/jobs/*.vars` depuis `config.py`
2. Déploie dans l'ordre : `consul → vault → traefik → postgres → mongodb → rustfs → user-service → offer-service → web`
3. Gère automatiquement l'init/unseal Vault au premier démarrage

### 4. Hostnames locaux

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

## Commandes Make

```bash
make deploy   ENV=local          # Déployer tous les jobs dans l'ordre
make restart  ENV=local          # Arrêter tout (sauf consul) puis redéployer
make job      ENV=local JOB=<n>  # Déployer un seul job
make plan     ENV=local JOB=<n>  # Dry-run
make lint     ENV=local          # Valider tous les fichiers de job

make stop     JOB=<name>         # Arrêter un job
make stop-all                    # Arrêter les services applicatifs
make status                      # État de tous les jobs
make logs     JOB=<name>         # Tail des logs

make vault-unseal                # Unseal Vault après un redémarrage
make vault-init                  # Initialiser Vault (première fois)
make vault-bootstrap             # Bootstrapper les secrets
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
- Les `.vars` dans `environments/local/jobs/` sont **générés** par `generate_vars.py` — ne pas éditer manuellement.
- Vault démarre **scellé** après chaque redémarrage → `make vault-unseal` ou `make deploy` le gère automatiquement.
- Les fichiers `.nomad.hcl` sont **identiques entre local et prod** — seuls les `.vars` diffèrent.
- Pour les services applicatifs (contraintes d'env vars, port binding, healthcheck…) : voir [`docs/onboarding-services.md`](docs/onboarding-services.md).
- Pour le déploiement en production (multi-nœuds via Ansible) : voir [`docs/server-deployment.md`](docs/server-deployment.md).
sent
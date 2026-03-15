# kalyNow-infra

Infrastructure locale kalyNow basée sur **Nomad + Consul + Vault + Traefik**.

## Services gérés dans ce repo

| Service | Description | Port local |
|---------|-------------|-----------|
| Nomad | Orchestrateur | 4646 |
| Consul | Service discovery | 8500 |
| Vault | Secrets (persistent file storage) | 8200 |
| Traefik | API gateway / reverse proxy | 80, 8080 |
| PostgreSQL | DB relationnelle | 5432 |
| MongoDB | DB documentaire | 27017 |
| RustFS | Stockage S3-compatible | 9000, 9001 |
| user-service | API users | 3001 |
| offer-service | API offers | 3000 |

## 1) Prérequis local

- Linux
- Docker Engine installé et démarré
- `nomad` CLI/agent installé
- `python3` (pour bootstrap Vault)

### Installation rapide de Nomad (local)

Exemple binaire officiel :

```bash
curl -LO https://releases.hashicorp.com/nomad/1.11.3/nomad_1.11.3_linux_amd64.zip
unzip nomad_1.11.3_linux_amd64.zip
sudo install nomad /usr/local/bin/nomad
nomad version
```

## 2) Configuration Nomad locale

> ⚠️ **Règle** : ne jamais éditer directement `/etc/nomad.d/`.
> Toujours modifier les fichiers dans `nomad/config/` puis les copier sur le système.

| Fichier repo | Destination système |
|---|---|
| `nomad/config/nomad.hcl` | `/etc/nomad.d/nomad.hcl` |
| `nomad/config/volumes.hcl` | `/etc/nomad.d/volumes.hcl` |

Copier la config (après chaque modification dans le repo) :

```bash
sudo mkdir -p /etc/nomad.d
sudo cp nomad/config/nomad.hcl /etc/nomad.d/nomad.hcl
sudo cp nomad/config/volumes.hcl /etc/nomad.d/volumes.hcl
```

### Volumes hôtes requis

Créer les dossiers des volumes persistants avec les bonnes permissions (une seule fois) :

```bash
sudo mkdir -p /opt/nomad/volumes/{postgres,mongodb,rustfs}
```

Les déclarations sont dans [`nomad/config/volumes.hcl`](nomad/config/volumes.hcl).
Pour ajouter un volume : modifier ce fichier → `sudo cp` → `/etc/nomad.d/volumes.hcl` → recharger Nomad.

```hcl
client {
    host_volume "postgres_data" {
        path      = "/opt/nomad/volumes/postgres"
        read_only = false
    }

    host_volume "mongo_data" {
        path      = "/opt/nomad/volumes/mongodb"
        read_only = false
    }

    host_volume "rustfs_data" {
        path      = "/opt/nomad/volumes/rustfs"
        read_only = false
    }
}
```

### Lancer Nomad en local

```bash
sudo mkdir -p /nomad/data
nomad agent -config=/etc/nomad.d
```

Dans un autre terminal :

```bash
export NOMAD_ADDR=http://127.0.0.1:4646
```

## 3) Hostnames locaux (important pour Traefik)

Ajouter dans `/etc/hosts` :

```txt
127.0.0.1 kalynow.mg traefik.kalynow.mg vault.kalynow.mg
```

## 4) Déploiement local (ordre recommandé)

Depuis la racine `kalyNow-infra/` :

```bash
export NOMAD_ADDR=http://127.0.0.1:4646

# 1) Discovery
nomad job run nomad/jobs/consul.nomad.hcl

# 2) Secrets
nomad job run nomad/jobs/vault.nomad.hcl
```

Bootstrap Vault (first time only):

```bash
cp scripts/config.example.py scripts/config.py
# Fill in credentials in scripts/config.py

# Step 1 — Initialize Vault (generates root token + unseal keys)
python3 scripts/bootstrap_vault.py --init --config scripts/config.py
# Saves keys to scripts/.vault-init.json  ← back this file up securely!
# Writes VAULT_TOKEN into config.py automatically.

# Step 2 — Write all secrets and configure JWT auth
python3 scripts/bootstrap_vault.py --config scripts/config.py
```

After every Vault restart (host reboot, container restart):

```bash
# Vault starts sealed — unseal in one command:
python3 scripts/bootstrap_vault.py --unseal-only --config scripts/config.py
```

Puis déployer le reste :

```bash
nomad job run nomad/jobs/postgres.nomad.hcl
nomad job run nomad/jobs/mongodb.nomad.hcl
nomad job run nomad/jobs/rustfs.nomad.hcl

nomad job run nomad/jobs/user-service.nomad.hcl
nomad job run nomad/jobs/offer-service.nomad.hcl

nomad job run nomad/jobs/traefik.nomad.hcl
```

## 5) URLs utiles en dev

- Nomad UI: http://127.0.0.1:4646
- Consul UI: http://127.0.0.1:8500
- Vault UI: http://127.0.0.1:8200/ui
- Traefik Dashboard: http://traefik.kalynow.mg
- User Swagger: http://kalynow.mg/api/us/
- Offer Swagger: http://kalynow.mg/api/of/

## 6) Vérifications et commandes utiles

```bash
nomad status
nomad status traefik
nomad status user-service
nomad status offer-service
```

Lister les routeurs Traefik chargés :

```bash
curl -s http://127.0.0.1:8080/api/http/routers | jq -r '.[].name'
```

## Notes

- Setup **dev local uniquement**.
- Vault tourne en mode **serveur avec stockage fichier** — les secrets survivent aux redémarrages.
- Le fichier `scripts/.vault-init.json` contient les clés de dévérouillage et le root token — **ne jamais committer ce fichier**.
- Traefik lit les routes depuis Consul (`consulCatalog`), via les tags des jobs Nomad.

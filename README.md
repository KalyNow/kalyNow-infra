# kalyNow-infra

Infrastructure locale kalyNow basée sur **Nomad + Consul + Vault + Traefik**.

## Services gérés dans ce repo

| Service | Description | Port local |
|---------|-------------|-----------|
| Nomad | Orchestrateur | 4646 |
| Consul | Service discovery | 8500 |
| Vault (dev) | Secrets | 8200 |
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

Le fichier principal du repo est [nomad/config/nomad.hcl](nomad/config/nomad.hcl).  
Copier dans la config locale Nomad :

```bash
sudo mkdir -p /etc/nomad.d
sudo cp nomad/config/nomad.hcl /etc/nomad.d/nomad.hcl
```

### Volumes hôtes requis

Créer les dossiers des volumes persistants :

```bash
sudo mkdir -p /opt/nomad/volumes/{postgres,mongodb,rustfs,kafka,redis,clickhouse}
```

Puis déclarer ces volumes dans Nomad (ex: `/etc/nomad.d/host_volumes.hcl`) :

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

    host_volume "kafka_data" {
        path      = "/opt/nomad/volumes/kafka"
        read_only = false
    }

    host_volume "redis_data" {
        path      = "/opt/nomad/volumes/redis"
        read_only = false
    }

    host_volume "clickhouse_data" {
        path      = "/opt/nomad/volumes/clickhouse"
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

Bootstrap Vault (une fois après reset) :

```bash
cp scripts/config.example.py scripts/config.py
# éditer scripts/config.py
python3 scripts/bootstrap_vault.py --config scripts/config.py
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
- Vault est lancé en mode `-dev` dans ce projet.
- Traefik lit les routes depuis Consul (`consulCatalog`), via les tags des jobs Nomad.

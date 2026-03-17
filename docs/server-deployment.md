# Server Deployment (multi-node)

Production server provisioning is fully automated with **Ansible**.
The playbooks live in `ansible/` inside this repository.

---

## Architecture cible

```
node-server  (Nomad server + client)
  └── Vault, Consul, Traefik, Postgres, MongoDB, RustFS

node-client  (Nomad client only)
  └── user-service, offer-service, web
```

- **Consul** runs as `type = "system"` — scheduled on every node automatically.
- **Vault** is pinned on the server node via a Nomad meta constraint (`meta.vault_server = "true"`).
- Traffic enters through **nginx** (TLS termination) → **Traefik** → services on dynamic Nomad ports.
- All Nomad RPC and HTTP traffic is **mutually TLS-authenticated**.
- Nomad **ACL** is enabled — a root token is generated once on bootstrap.

---

## Prérequis sur la machine de déploiement (votre poste)

| Outil | Version minimale |
|-------|-----------------|
| Ansible | ≥ 2.16 |
| Python | ≥ 3.11 |
| Nomad CLI | ≥ 1.11 (pour générer les certs TLS) |
| SSH | clé déployée sur chaque serveur |

### Installer Ansible

```bash
# Via pip (recommandé)
pip install --upgrade ansible

# Debian / Ubuntu
sudo apt update && sudo apt install -y ansible

# Fedora / RHEL
sudo dnf install -y ansible
```

### Installer le CLI Nomad (pour la génération TLS uniquement)

```bash
curl -LO https://releases.hashicorp.com/nomad/1.11.3/nomad_1.11.3_linux_amd64.zip
unzip nomad_1.11.3_linux_amd64.zip && sudo install nomad /usr/local/bin/nomad
```

---

## Structure Ansible

```
ansible/
├── ansible.cfg                          # configuration Ansible
├── site.yml                             # playbook principal (full provisioning)
├── add-client.yml                       # ajouter un nouveau noeud client
├── reconfigure.yml                      # pousser un changement de config
├── inventory/
│   ├── hosts.yml                        # inventaire structurel (aliases uniquement)
│   └── group_vars/
│       ├── cluster.yml      ← ✏️  SEUL FICHIER À ÉDITER
│       ├── all.yml                      # variables partagées (datacenter, volumes…)
│       ├── nomad_servers.yml            # variables des noeuds serveur
│       └── nomad_clients.yml            # variables des noeuds client
└── roles/
    ├── nomad_install/           # installe Nomad via apt (HashiCorp repo)
    ├── nomad_tls/               # génère les certs TLS et les distribue
    ├── nomad_configure/         # déploie les configs HCL (templates Jinja2)
    ├── nomad_volumes/           # crée les répertoires de volumes
    └── nomad_acl/               # bootstrap ACL (une seule fois)
```

---

## Configuration du cluster — `cluster.yml`

> ✅ **C'est le seul fichier à modifier pour configurer ou migrer un cluster.**

```yaml
# ansible/inventory/group_vars/cluster.yml

# IP du serveur Nomad (server + client)
nomad_server_ip: "1.2.3.4"

# IPs des noeuds clients
nomad_clients_ips:
  client1: "5.6.7.8"
  # client2: "9.10.11.12"   # ajouter d'autres clients ici

# Utilisateur SSH
ansible_user: "root"                          # ou "ubuntu" selon l'image
ansible_ssh_private_key_file: "~/.ssh/id_ed25519"

# SANs TLS supplémentaires (optionnel)
tls_extra_ips: []
tls_extra_dns: []
```

Les SANs du certificat TLS serveur sont **calculés automatiquement** à partir de `nomad_server_ip`,
de toutes les IPs de `nomad_clients_ips`, et de `127.0.0.1`. Rien d'autre à configurer.

---

## Déploiement initial

### 1. Déployer votre clé SSH sur chaque serveur

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<SERVER_IP>
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<CLIENT_IP>
```

### 2. Renseigner `cluster.yml`

Éditer `ansible/inventory/group_vars/cluster.yml` avec les IPs de vos serveurs.

### 3. Lancer le provisioning complet

```bash
cd ansible
ansible-playbook site.yml
```

Ce que fait `site.yml` dans l'ordre :

| Phase | Tag | Description |
|-------|-----|-------------|
| 1 | `tls` | Génère CA + certs sur le contrôleur, distribue sur les noeuds |
| 2 | `install` | Installe Nomad via apt (HashiCorp repo) sur tous les noeuds |
| 3 | `volumes` | Crée les répertoires de volumes host |
| 4 | `configure` | Déploie `server.hcl` / `client.hcl` / `vault.hcl` / `volumes.hcl` |
| 5 | `service` | Active et démarre `nomad` via systemd |
| 6 | `acl` | Bootstrap ACL Nomad (une seule fois) — token sauvé dans `.nomad-bootstrap-token` |
| 7 | `verify` | Affiche `nomad node status` |

### 4. Vérifier le cluster

```bash
nomad node status
# Attendu : tous les noeuds en état "ready"
```

---

## Changer de serveur

Pour migrer sur de nouveaux VPS (ou tester sur des VMs locales) :

1. **Mettre à jour `cluster.yml`** avec les nouvelles IPs
2. **Supprimer les anciens certs TLS** (liés aux anciennes IPs) :
   ```bash
   rm -rf tls/
   ```
3. **Supprimer l'ancien token ACL** :
   ```bash
   rm -f .nomad-bootstrap-token
   ```
4. **Redéployer** :
   ```bash
   cd ansible && ansible-playbook site.yml
   ```

---

## Opérations courantes

### Ajouter un noeud client

1. Ajouter son IP dans `cluster.yml` sous `nomad_clients_ips` :
   ```yaml
   nomad_clients_ips:
     client1: "5.6.7.8"
     client2: "9.10.11.12"   # nouveau
   ```
2. Ajouter l'alias correspondant dans `inventory/hosts.yml` sous `nomad_clients`
3. Lancer :
   ```bash
   ansible-playbook add-client.yml --limit client2
   ```

### Pousser un changement de configuration

```bash
ansible-playbook reconfigure.yml
# ou sur un seul noeud :
ansible-playbook reconfigure.yml --limit client1
```

### Relancer uniquement une phase

```bash
ansible-playbook site.yml --tags tls          # re-générer les certs
ansible-playbook site.yml --tags configure    # pousser les configs HCL
ansible-playbook site.yml --tags acl          # re-bootstrapper l'ACL
```

---

## Fichiers secrets — ne jamais committer

| Fichier | Contenu |
|---------|---------|
| `tls/` | CA, clés privées TLS (générées au déploiement) |
| `.nomad-bootstrap-token` | Token root ACL Nomad |
| `scripts/config.py` | Credentials Vault / services |
| `scripts/.vault-init.json` | Clés unseal + root token Vault |

Ces entrées sont dans `.gitignore`.

---

## Volumes host créés par Ansible

| Volume | Chemin | Owner |
|--------|--------|-------|
| `postgres_data` | `/opt/nomad/volumes/postgres` | `root:root` |
| `mongo_data` | `/opt/nomad/volumes/mongodb` | `root:root` |
| `redis_data` | `/opt/nomad/volumes/redis` | `root:root` |
| `rustfs_data` | `/opt/nomad/volumes/rustfs` | `10001:10001` |
| `kafka_data` | `/opt/nomad/volumes/kafka` | `root:root` |
| `clickhouse_data` | `/opt/nomad/volumes/clickhouse` | `root:root` |
| `vault_data` | `/opt/nomad/volumes/vault` | `100:100` |

> ⚠️ Les jobs Nomad avec `volume { type = "host" }` ne peuvent scheduler que sur les noeuds ayant le volume déclaré dans `volumes.hcl`.

---

## Architecture réseau

```
nginx :80/:443  →  Traefik :8888  →  services (ports dynamiques Nomad)
```

---

## Voir aussi

- [README.md](../README.md) — développement local single-node
- [onboarding-services.md](onboarding-services.md) — ajouter un nouveau service

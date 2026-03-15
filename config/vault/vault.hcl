# Vault server configuration — persistent file storage
# Replaces dev mode so state survives container/host restarts.
#
# Data is stored in /vault/data which is mounted from a Nomad host volume
# (vault_data → /opt/nomad/volumes/vault_data on the host).
#
# Vault starts sealed after every restart. Run the unseal step:
#   python3 scripts/bootstrap_vault.py --unseal-only --config scripts/config.py

storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true   # TLS terminated by Traefik in this setup
}

cluster_addr = "http://127.0.0.1:8201"
api_addr     = "http://127.0.0.1:8200"

ui = true

# Disable mlock — required when IPC_LOCK capability is unavailable
disable_mlock = true

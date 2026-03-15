# KalyNow – HashiCorp Vault
#
# Runs Vault in dev mode (single-node, in-memory).
# Root token = "root"  →  set VAULT_TOKEN=root in your shell.
#
# After first deploy, bootstrap secrets with:
#
#   cp scripts/config.example.py scripts/config.py
#   # Fill in config.py with your credentials
#   python3 scripts/bootstrap_vault.py --config scripts/config.py
#
# This will:
#   1. Enable KV v2 secrets engine
#   2. Write kalynow-services policy
#   3. Enable JWT auth backend for Nomad Workload Identity
#   4. Write all infra + service secrets
#
# Auth: Nomad tasks authenticate via Workload Identity (JWT).
#       No static Vault token is needed on Nomad side.
#
# Deploy:  nomad job run nomad/jobs/vault.nomad.hcl
# UI:      http://127.0.0.1:8200/ui  (token: root)

job "vault" {
  datacenters = ["dc1"]
  type        = "service"

  group "vault" {
    count = 1

    network {
      port "http"    { static = 8200 }
      port "cluster" { static = 8201 }
    }

    task "vault" {
      driver = "docker"

      config {
        image        = "hashicorp/vault:1.17"
        ports        = ["http", "cluster"]
        network_mode = "host"

        args = [
          "server",
          "-dev",
          "-dev-root-token-id=root",
          "-dev-listen-address=0.0.0.0:8200",
        ]
      }

      env {
        VAULT_DEV_ROOT_TOKEN_ID = "root"
        VAULT_ADDR              = "http://127.0.0.1:8200"
        # Disable mlock — required when IPC_LOCK capability is unavailable (Podman dev mode)
        VAULT_DISABLE_MLOCK     = "true"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "vault"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.vault.rule=Host(`vault.kalynow.mg`)",
          "traefik.http.routers.vault.entrypoints=web",
          "traefik.http.services.vault.loadbalancer.server.port=8200",
        ]

        check {
          type     = "http"
          path     = "/v1/sys/health"
          port     = "http"
          interval = "10s"
          timeout  = "3s"
        }
      }
    }
  }
}

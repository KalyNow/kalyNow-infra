# KalyNow – HashiCorp Vault
#
# Runs Vault in SERVER mode with file storage — state persists across restarts.
# Secrets are stored in /opt/nomad/volumes/vault on the host.
#
# The Vault server config is inlined in the template{} block below.
# The canonical copy lives in config/vault/vault.hcl — keep them in sync.
#   1. Deploy this job:
#        nomad job run nomad/jobs/vault.nomad.hcl
#
#   2. Initialize Vault (once, generates root token + unseal keys):
#        python3 scripts/bootstrap_vault.py --init --config scripts/config.py
#      This writes scripts/.vault-init.json  ← keep this file safe & private!
#      It also sets VAULT_TOKEN in config.py automatically.
#
#   3. Bootstrap all secrets (once):
#        python3 scripts/bootstrap_vault.py --config scripts/config.py
#
# ── After every Vault restart (host reboot, container restart) ────────────────
#   Vault starts sealed — unseal it in one command:
#        python3 scripts/bootstrap_vault.py --unseal-only --config scripts/config.py
#
# ── After a full wipe (volume deleted) ───────────────────────────────────────
#   Repeat steps 2 and 3 above.
#
# Auth: Nomad tasks authenticate via Workload Identity (JWT).
#       No static Vault token is needed on the Nomad side.
#
# Deploy:  nomad job run nomad/jobs/vault.nomad.hcl
# UI:      http://127.0.0.1:8200/ui

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "vault_image" {
  type    = string
  default = "hashicorp/vault:1.17"
}

variable "vault_cpu" {
  type    = number
  default = 200
}

variable "vault_memory" {
  type    = number
  default = 256
}

variable "domain" {
  type    = string
  default = "kalynow.mg"
}

job "vault" {
  datacenters = [var.datacenter]
  type        = "service"

  # Pin Vault to the node that has meta.vault_server = "true".
  # This ensures the deploy script can always reach it at 127.0.0.1:8200.
  constraint {
    attribute = "${meta.vault_server}"
    value     = "true"
  }

  group "vault" {
    count = 1

    network {
      port "http"    { static = 8200 }
      port "cluster" { static = 8201 }
    }

    # Persistent volume — survives container and host restarts
    volume "vault_data" {
      type   = "host"
      source = "vault_data"
    }

    task "vault" {
      driver = "docker"

      config {
        image        = var.vault_image
        ports        = ["http", "cluster"]
        network_mode = "host"

        args = [
          "server",
            "-config=/local/vault.hcl",
        ]
      }

      # Inline Vault server config — keep in sync with config/vault/vault.hcl
      template {
          destination = "local/vault.hcl"
        change_mode = "restart"
        data        = <<EOF
storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

cluster_addr = "http://127.0.0.1:8201"
api_addr     = "http://127.0.0.1:8200"

ui = true

disable_mlock = true
EOF
      }

      volume_mount {
        volume      = "vault_data"
        destination = "/vault/data"
      }

      env {
        VAULT_ADDR          = "http://127.0.0.1:8200"
        VAULT_DISABLE_MLOCK = "true"
      }

      resources {
        cpu    = var.vault_cpu
        memory = var.vault_memory
      }

      service {
        name = "vault"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.vault.rule=Host(`vault.${var.domain}`)",
          "traefik.http.routers.vault.entrypoints=web",
          "traefik.http.services.vault.loadbalancer.server.port=8200",
        ]

        # /v1/sys/health returns 200 when initialized+unsealed,
        # 429 when standby, 501 when not initialized, 503 when sealed.
        # Nomad marks the service healthy on any 2xx/429.
        check {
          type     = "http"
          path     = "/v1/sys/health?standbyok=true&uninitcode=200&sealedcode=200"
          port     = "http"
          interval = "10s"
          timeout  = "3s"
        }
      }
    }
  }
}

# KalyNow Offer Service — NestJS
#
# Runs directly on the host via raw_exec (no container overhead in dev).
# Consul registers it, Traefik routes /api/of → this service.
#
# Deploy:  nomad job run nomad/jobs/offer-service.nomad.hcl
# Logs:    nomad alloc logs <alloc-id>

job "offer-service" {
  datacenters = ["dc1"]
  type        = "service"

  group "offer-service" {
    count = 1

    network {
      port "http" { static = 3000 }
    }

    task "offer-service" {
      driver = "docker"

      # Workload Identity for Vault (Nomad 1.7+)
      identity {
        name         = "vault_default"
        aud          = ["vault.io"]
        change_mode  = "restart"
        ttl          = "1h"
      }

      vault {
        role        = "nomad-workloads"
        change_mode = "restart"
      }

      config {
        image        = "kalynow/offer-service:local"
        ports        = ["http"]
        network_mode = "host"
        force_pull   = false
      }

      template {
        destination = "secrets/offer.env"
        env         = true
        data        = <<EOF
PORT=3000
{{ with secret "secret/data/kalynow/offer-service" }}
MONGODB_URI={{ .Data.data.MONGODB_URI }}
# Same node IP as this task (dynamic, no hardcoded host IP)
RUSTFS_ENDPOINT=http://{{ env "NOMAD_IP_http" }}:9000
RUSTFS_ACCESS_KEY={{ .Data.data.RUSTFS_ACCESS_KEY }}
RUSTFS_SECRET_KEY={{ .Data.data.RUSTFS_SECRET_KEY }}
RUSTFS_BUCKET={{ .Data.data.RUSTFS_BUCKET }}
RUSTFS_REGION={{ .Data.data.RUSTFS_REGION }}
{{ end }}
EOF
      }

      resources {
        cpu    = 300
        memory = 256
      }

      service {
        name = "offer-service"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.offers.rule=Host(`kalynow.mg`) && PathPrefix(`/api/of`)",
          "traefik.http.routers.offers.entrypoints=web",
          "traefik.http.routers.offers.middlewares=offers-trailing-slash,offers-docs-shortcut,strip-offers-prefix",
          "traefik.http.middlewares.offers-trailing-slash.redirectregex.regex=^https?://kalynow\\.mg/api/of$",
          "traefik.http.middlewares.offers-trailing-slash.redirectregex.replacement=http://kalynow.mg/api/of/",
          "traefik.http.middlewares.offers-trailing-slash.redirectregex.permanent=true",
          "traefik.http.middlewares.offers-docs-shortcut.replacepathregex.regex=^/api/of/?$",
          "traefik.http.middlewares.offers-docs-shortcut.replacepathregex.replacement=/api",
          "traefik.http.middlewares.strip-offers-prefix.stripprefix.prefixes=/api/of",
          "traefik.http.services.offer-service.loadbalancer.server.port=3000",
        ]

        check {
          type     = "http"
          path     = "/api"
          port     = "http"
          interval = "10s"
          timeout  = "3s"
        }
      }
    }
  }
}

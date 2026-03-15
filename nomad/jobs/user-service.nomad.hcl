# KalyNow User Service — NestJS
#
# Consul registers it, Traefik routes /api/us → this service.

job "user-service" {
  datacenters = ["dc1"]
  type        = "service"

  group "user-service" {
    count = 1

    network {
      port "http" { static = 3001 }
    }

    task "user-service" {
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
        image        = "kalynow/user-service:local"
        ports        = ["http"]
        network_mode = "host"
        force_pull   = false
      }

      template {
        destination = "secrets/user.env"
        env         = true
        data        = <<EOF
PORT=3001
{{- with secret "secret/data/kalynow/user-service" }}
DATABASE_URL={{ .Data.data.DATABASE_URL }}
JWT_SECRET={{ .Data.data.JWT_SECRET }}
JWT_EXPIRES_IN={{ .Data.data.JWT_EXPIRES_IN }}
{{- end }}
EOF
      }

      resources {
        cpu    = 300
        memory = 256
      }

      service {
        name = "user-service"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.users.rule=Host(`kalynow.mg`) && PathPrefix(`/api/us`)",
          "traefik.http.routers.users.entrypoints=web",
          "traefik.http.routers.users.middlewares=users-trailing-slash,users-docs-shortcut,strip-users-prefix",
          "traefik.http.middlewares.users-trailing-slash.redirectregex.regex=^https?://kalynow\\.mg/api/us$",
          "traefik.http.middlewares.users-trailing-slash.redirectregex.replacement=http://kalynow.mg/api/us/",
          "traefik.http.middlewares.users-trailing-slash.redirectregex.permanent=true",
          "traefik.http.middlewares.users-docs-shortcut.replacepathregex.regex=^/api/us/?$",
          "traefik.http.middlewares.users-docs-shortcut.replacepathregex.replacement=/api",
          "traefik.http.middlewares.strip-users-prefix.stripprefix.prefixes=/api/us",
          "traefik.http.services.user-service.loadbalancer.server.port=3001",
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

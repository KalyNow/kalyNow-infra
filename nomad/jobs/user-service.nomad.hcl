# KalyNow User Service — NestJS
#
# Consul registers it, Traefik routes /api/us → this service.

job "user-service" {
  datacenters = ["dc1"]
  type        = "service"

  group "user-service" {
    count = 1

    network {
      port "http" {}
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
PORT={{ env "NOMAD_PORT_http" }}
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
          "traefik.http.routers.users.middlewares=users-cors,users-trailing-slash,users-docs-shortcut,strip-users-prefix",

          # CORS — autorise localhost (dev) + kalynow.mg (prod)
          "traefik.http.middlewares.users-cors.headers.accesscontrolallowmethods=GET,POST,PUT,PATCH,DELETE,OPTIONS",
          "traefik.http.middlewares.users-cors.headers.accesscontrolalloworiginlist=http://localhost:5173,http://localhost:3000,http://localhost:4173,https://kalynow.mg,http://kalynow.mg",
          "traefik.http.middlewares.users-cors.headers.accesscontrolallowheaders=Content-Type,Authorization,Accept,X-Requested-With",
          "traefik.http.middlewares.users-cors.headers.accesscontrolexposeheaders=Authorization",
          "traefik.http.middlewares.users-cors.headers.accesscontrolmaxage=86400",
          "traefik.http.middlewares.users-cors.headers.addvaryheader=true",

          "traefik.http.middlewares.users-trailing-slash.redirectregex.regex=^https?://kalynow\\.mg/api/us$",
          "traefik.http.middlewares.users-trailing-slash.redirectregex.replacement=http://kalynow.mg/api/us/",
          "traefik.http.middlewares.users-trailing-slash.redirectregex.permanent=true",
          "traefik.http.middlewares.users-docs-shortcut.replacepathregex.regex=^/api/us/?$",
          "traefik.http.middlewares.users-docs-shortcut.replacepathregex.replacement=/api",
          "traefik.http.middlewares.strip-users-prefix.stripprefix.prefixes=/api/us",
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

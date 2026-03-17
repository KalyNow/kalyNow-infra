# KalyNow User Service — NestJS
#
# Consul registers it, Traefik routes /api/us → this service.
#
# Deploy (local): nomad job run -var-file=environments/local/nomad.vars jobs/user-service.nomad.hcl
# Deploy (prod):  nomad job run -var-file=environments/prod/nomad.vars  jobs/user-service.nomad.hcl

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "user_service_count" {
  type    = number
  default = 1
}

variable "user_service_image" {
  type    = string
  default = "kalynow/user-service:local"
}

variable "user_service_cpu" {
  type    = number
  default = 300
}

variable "user_service_memory" {
  type    = number
  default = 256
}

variable "domain" {
  type    = string
  default = "kalynow.mg"
}

variable "vault_role" {
  type    = string
  default = "nomad-workloads"
}

variable "force_pull" {
  type    = bool
  default = false
}

job "user-service" {
  datacenters = [var.datacenter]
  type        = "service"

  group "user-service" {
    count = var.user_service_count

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
        role        = var.vault_role
        change_mode = "restart"
      }

      config {
        image        = var.user_service_image
        ports        = ["http"]
        network_mode = "host"
        force_pull   = var.force_pull
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
        cpu    = var.user_service_cpu
        memory = var.user_service_memory
      }

      service {
        name = "user-service"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.users.rule=Host(`${var.domain}`) && PathPrefix(`/api/us`)",
          "traefik.http.routers.users.entrypoints=web",
          "traefik.http.routers.users.middlewares=users-cors,users-trailing-slash,users-docs-shortcut,strip-users-prefix",

          # CORS — autorise localhost (dev) + domain (prod)
          "traefik.http.middlewares.users-cors.headers.accesscontrolallowmethods=GET,POST,PUT,PATCH,DELETE,OPTIONS",
          "traefik.http.middlewares.users-cors.headers.accesscontrolalloworiginlist=http://localhost:5173,http://localhost:3000,http://localhost:4173,https://${var.domain},http://${var.domain}",
          "traefik.http.middlewares.users-cors.headers.accesscontrolallowheaders=Content-Type,Authorization,Accept,X-Requested-With",
          "traefik.http.middlewares.users-cors.headers.accesscontrolexposeheaders=Authorization",
          "traefik.http.middlewares.users-cors.headers.accesscontrolmaxage=86400",
          "traefik.http.middlewares.users-cors.headers.addvaryheader=true",

          "traefik.http.middlewares.users-trailing-slash.redirectregex.regex=^https?://${var.domain}/api/us$$",
          "traefik.http.middlewares.users-trailing-slash.redirectregex.replacement=http://${var.domain}/api/us/",
          "traefik.http.middlewares.users-trailing-slash.redirectregex.permanent=true",
          "traefik.http.middlewares.users-docs-shortcut.replacepathregex.regex=^/api/us/?$$",
          "traefik.http.middlewares.users-docs-shortcut.replacepathregex.replacement=/api",
          "traefik.http.middlewares.strip-users-prefix.stripprefix.prefixes=/api/us",

          # Internal router — no Host rule, matched by forwardauth via 127.0.0.1
          # Path /auth/verify is forwarded as-is to user-service (no strip)
          "traefik.http.routers.users-internal.rule=PathPrefix(`/auth/verify`)",
          "traefik.http.routers.users-internal.entrypoints=web",
          "traefik.http.routers.users-internal.priority=100",
          "traefik.http.routers.users-internal.service=user-service",
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

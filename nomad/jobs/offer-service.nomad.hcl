# KalyNow Offer Service — NestJS
#
# Consul registers it, Traefik routes /api/of → this service.
#
# Deploy (local): nomad job run -var-file=environments/local/nomad.vars jobs/offer-service.nomad.hcl
# Deploy (prod):  nomad job run -var-file=environments/prod/nomad.vars  jobs/offer-service.nomad.hcl
# Logs:    nomad alloc logs <alloc-id>

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "offer_service_count" {
  type    = number
  default = 1
}

variable "offer_service_image" {
  type    = string
  default = "kalynow/offer-service:local"
}

variable "offer_service_cpu" {
  type    = number
  default = 300
}

variable "offer_service_memory" {
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

job "offer-service" {
  datacenters = [var.datacenter]
  type        = "service"

  group "offer-service" {
    count = var.offer_service_count

    network {
      port "http" {}
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
        role        = var.vault_role
        change_mode = "restart"
      }

      config {
        image        = var.offer_service_image
        ports        = ["http"]
        network_mode = "host"
        force_pull   = var.force_pull
      }

      template {
        destination = "secrets/offer.env"
        env         = true
        data        = <<EOF
PORT={{ env "NOMAD_PORT_http" }}
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
          "traefik.http.routers.offers.middlewares=offers-trailing-slash,offers-docs-shortcut,offers-auth,strip-offers-prefix",
          "traefik.http.middlewares.offers-trailing-slash.redirectregex.regex=^https?://kalynow\\.mg/api/of$",
          "traefik.http.middlewares.offers-trailing-slash.redirectregex.replacement=http://kalynow.mg/api/of/",
          "traefik.http.middlewares.offers-trailing-slash.redirectregex.permanent=true",
          "traefik.http.middlewares.offers-docs-shortcut.replacepathregex.regex=^/api/of/?$",
          "traefik.http.middlewares.offers-docs-shortcut.replacepathregex.replacement=/api",
          "traefik.http.middlewares.offers-auth.forwardauth.address=http://kalynow.mg/api/us/auth/verify",
          "traefik.http.middlewares.offers-auth.forwardauth.trustForwardHeader=true",
          "traefik.http.middlewares.offers-auth.forwardauth.authRequestHeaders=Authorization",
          "traefik.http.middlewares.offers-auth.forwardauth.authResponseHeaders=X-User-Id,X-User-Email,X-User-Role",
          "traefik.http.middlewares.strip-offers-prefix.stripprefix.prefixes=/api/of",
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

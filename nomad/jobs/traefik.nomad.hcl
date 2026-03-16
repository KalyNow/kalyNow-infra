# Traefik — API gateway + reverse proxy
#
# Reads service routes from Consul catalog (tags on each service{} block).
# No Docker socket, no static file routes — pure service discovery.
#
# Entrypoints:
#   web        :80   → HTTP traffic (default → SPA at domain)
#   websecure  :443  → HTTPS traffic
#   traefik    :8080 → dashboard (traefik.domain)
#
# Deploy (local): nomad job run -var-file=environments/local/nomad.vars jobs/traefik.nomad.hcl
# Deploy (prod):  nomad job run -var-file=environments/prod/nomad.vars  jobs/traefik.nomad.hcl

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "traefik_image" {
  type    = string
  default = "traefik:v3.3"
}

variable "traefik_cpu" {
  type    = number
  default = 200
}

variable "traefik_memory" {
  type    = number
  default = 128
}

variable "domain" {
  type    = string
  default = "kalynow.mg"
}

variable "traefik_dashboard_enabled" {
  type    = bool
  default = true
}

variable "traefik_dashboard_subdomain" {
  type    = string
  default = "traefik"
}

job "traefik" {
  datacenters = [var.datacenter]
  type        = "service"

  group "traefik" {
    count = 1

    network {
      port "http"      { static = 80 }
      port "dashboard" { static = 8080 }
    }

    task "traefik" {
      driver = "docker"

      config {
        image        = var.traefik_image
        network_mode = "host"
        args         = ["--configFile=/local/traefik.yml"]
      }

      # Traefik static config — injected at runtime via Nomad template
      template {
        destination = "local/traefik.yml"
        data        = <<EOF
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: true

ping: {}

entryPoints:
  # Default entrypoint — all HTTP traffic, default route goes to the web SPA
  web:
    address: ":80"
  # TLS entrypoint — ready for HTTPS when certs are added
  websecure:
    address: ":443"
  # Dashboard entrypoint — Traefik UI only
  traefik:
    address: ":8080"

# Consul catalog provider — routes discovered from service tags
# No Docker socket, no static files needed
providers:
  consulCatalog:
    endpoint:
      address: "127.0.0.1:8500"
    exposedByDefault: false
    prefix: traefik
    refreshInterval: 5s

log:
  level: INFO

accessLog: {}
EOF
      }

      resources {
        cpu    = var.traefik_cpu
        memory = var.traefik_memory
      }

      service {
        name = "traefik"
        port = "dashboard"

        tags = [
          "traefik.enable=${var.traefik_dashboard_enabled}",
          # Dashboard served on the dedicated traefik entrypoint (:8080)
          "traefik.http.routers.traefik-ui.rule=Host(`${var.traefik_dashboard_subdomain}.${var.domain}`)",
          "traefik.http.routers.traefik-ui.service=api@internal",
          "traefik.http.routers.traefik-ui.entrypoints=traefik",
        ]

        check {
          type     = "http"
          path     = "/ping"
          port     = "dashboard"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}

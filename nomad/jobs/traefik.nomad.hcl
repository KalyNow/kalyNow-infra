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

variable "traefik_http_port" {
  type    = number
  default = 80
}

variable "traefik_dashboard_port" {
  type    = number
  default = 8080
}

# Set to true when Traefik is behind a reverse proxy (nginx) that handles TLS.
# Enables forwardedHeaders trusting 127.0.0.1 so X-Forwarded-Proto is respected.
variable "traefik_behind_proxy" {
  type    = bool
  default = false
}

job "traefik" {
  datacenters = [var.datacenter]
  type        = "system"

  group "traefik" {

    network {
      port "http"      { static = var.traefik_http_port }
      port "dashboard" { static = var.traefik_dashboard_port }
    }

    task "traefik" {
      driver = "docker"

      config {
        image        = var.traefik_image
        network_mode = "host"
        args         = ["--configFile=/local/traefik.yml"]
      }

      env {
        TRAEFIK_HTTP_PORT    = "${var.traefik_http_port}"
        TRAEFIK_DASH_PORT    = "${var.traefik_dashboard_port}"
        TRAEFIK_BEHIND_PROXY = "${var.traefik_behind_proxy}"
      }

      # Traefik static config — injected at runtime via Nomad template
      # Variables are passed via env{} and read with {{ env "VAR" }} (Go template syntax)
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
  web:
    address: ":{{ env "TRAEFIK_HTTP_PORT" }}"
    {{- if eq (env "TRAEFIK_BEHIND_PROXY") "true" }}
    forwardedHeaders:
      trustedIPs:
        - "127.0.0.1"
    {{- end }}
  traefik:
    address: ":{{ env "TRAEFIK_DASH_PORT" }}"

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

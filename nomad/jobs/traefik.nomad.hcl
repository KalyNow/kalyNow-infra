# Traefik — API gateway + reverse proxy
#
# Reads service routes from Consul catalog (tags on each service{} block).
# No Docker socket, no static file routes — pure service discovery.
#
# Entrypoints:
#   web       :80   → HTTP traffic (kalynow.mg)
#   traefik   :8080 → dashboard (traefik.kalynow.mg)

job "traefik" {
  datacenters = ["dc1"]
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
        image        = "traefik:v3.3"
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

entryPoints:
  web:
    address: ":80"
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
        cpu    = 200
        memory = 128
      }

      service {
        name = "traefik"
        port = "dashboard"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.traefik-ui.rule=Host(`traefik.kalynow.mg`)",
          "traefik.http.routers.traefik-ui.service=api@internal",
          "traefik.http.routers.traefik-ui.entrypoints=web",
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

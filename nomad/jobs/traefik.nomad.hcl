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
        image = "traefik:v3.3"
        ports = ["http", "dashboard"]
        args  = ["--configFile=/etc/traefik/traefik.yml"]

        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock:ro",
          "local/traefik.yml:/etc/traefik/traefik.yml",
        ]
      }

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

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: kalyNow

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

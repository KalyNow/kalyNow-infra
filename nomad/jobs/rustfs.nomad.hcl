job "rustfs" {
  datacenters = ["dc1"]
  type        = "service"

  group "rustfs" {
    count = 1

    network {
      port "api"     { static = 9000 }
      port "console" { static = 9001 }
    }

    volume "rustfs_data" {
      type   = "host"
      source = "rustfs_data"
    }

    task "rustfs" {
      driver = "docker"

      config {
        image   = "rustfs/rustfs:1.0.0-alpha.85"
        ports   = ["api", "console"]
        args    = ["--console-enable", "/data"]
      }

      volume_mount {
        volume      = "rustfs_data"
        destination = "/data"
      }

      identity {
        name        = "vault_default"
        aud         = ["vault.io"]
        change_mode = "restart"
        ttl         = "1h"
      }

      vault {
        role        = "nomad-workloads"
        change_mode = "restart"
      }

      template {
        destination = "secrets/rustfs.env"
        env         = true
        data        = <<EOF
{{- with secret "secret/data/kalynow/rustfs" }}
RUSTFS_ACCESS_KEY={{ .Data.data.RUSTFS_ACCESS_KEY }}
RUSTFS_SECRET_KEY={{ .Data.data.RUSTFS_SECRET_KEY }}
{{- end }}
RUSTFS_CONSOLE_ENABLE=true
EOF
      }

      resources {
        cpu    = 300
        memory = 256
      }

      service {
        name = "rustfs-api"
        port = "api"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.rustfs.rule=Host(`kalynow.mg`) && PathPrefix(`/api/as`)",
          "traefik.http.routers.rustfs.entrypoints=web",
          "traefik.http.routers.rustfs.middlewares=strip-assets-prefix",
          "traefik.http.middlewares.strip-assets-prefix.stripprefix.prefixes=/api/as",
          "traefik.http.services.rustfs-api.loadbalancer.server.port=9000",
        ]

        check {
          type     = "http"
          path     = "/health/live"
          port     = "api"
          interval = "10s"
          timeout  = "2s"
        }
      }

      service {
        name = "rustfs-console"
        port = "console"
      }
    }
  }
}

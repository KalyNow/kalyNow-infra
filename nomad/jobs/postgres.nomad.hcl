job "postgres" {
  datacenters = ["dc1"]
  type        = "service"

  group "postgres" {
    count = 1

    network {
      mode = "host"
      port "postgres" { static = 5432 }
    }

    volume "postgres_data" {
      type   = "host"
      source = "postgres_data"
    }

    task "postgres" {
      driver = "docker"

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
        image        = "postgres:17-alpine"
        network_mode = "host"
      }

      volume_mount {
        volume      = "postgres_data"
        destination = "/var/lib/postgresql/data"
      }

      template {
        destination = "secrets/postgres.env"
        env         = true
        data        = <<EOF
{{- with secret "secret/data/kalynow/postgres" }}
POSTGRES_DB={{ .Data.data.POSTGRES_DB }}
POSTGRES_USER={{ .Data.data.POSTGRES_USER }}
POSTGRES_PASSWORD={{ .Data.data.POSTGRES_PASSWORD }}
{{- end }}
EOF
        change_mode = "restart"
      }

      resources {
        cpu    = 300
        memory = 256
      }

      service {
        name = "postgres"
        port = "postgres"

        check {
          type     = "tcp"
          port     = "postgres"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}

job "postgres" {
  datacenters = ["dc1"]
  type        = "service"

  group "postgres" {
    count = 1

    network {
      port "postgres" { static = 5432 }
    }

    volume "postgres_data" {
      type   = "host"
      source = "postgres_data"
    }

    task "postgres" {
      driver = "docker"

      config {
        image = "postgres:17-alpine"
        ports = ["postgres"]
      }

      volume_mount {
        volume      = "postgres_data"
        destination = "/var/lib/postgresql/data"
      }

      template {
        destination = "secrets/postgres.env"
        env         = true
        data        = <<EOF
POSTGRES_DB={{ env "NOMAD_META_postgres_db" | default "kalyNow" }}
POSTGRES_USER={{ env "NOMAD_META_postgres_user" | default "kalyNow" }}
POSTGRES_PASSWORD={{ env "NOMAD_META_postgres_password" | default "changeme" }}
EOF
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

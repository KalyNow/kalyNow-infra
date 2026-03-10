job "clickhouse" {
  datacenters = ["dc1"]
  type        = "service"

  group "clickhouse" {
    count = 1

    network {
      port "http"   { static = 8123 }
      port "native" { static = 9004 }
    }

    volume "clickhouse_data" {
      type   = "host"
      source = "clickhouse_data"
    }

    task "clickhouse" {
      driver = "docker"

      config {
        image = "clickhouse/clickhouse-server:25.3"
        ports = ["http", "native"]
      }

      volume_mount {
        volume      = "clickhouse_data"
        destination = "/var/lib/clickhouse"
      }

      template {
        destination = "secrets/clickhouse.env"
        env         = true
        data        = <<EOF
CLICKHOUSE_DB={{ env "NOMAD_META_clickhouse_db" | default "kalyNow" }}
CLICKHOUSE_USER={{ env "NOMAD_META_clickhouse_user" | default "kalyNow" }}
CLICKHOUSE_PASSWORD={{ env "NOMAD_META_clickhouse_password" | default "changeme" }}
EOF
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "clickhouse"
        port = "http"

        check {
          type     = "http"
          path     = "/ping"
          port     = "http"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}

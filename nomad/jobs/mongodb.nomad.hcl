job "mongodb" {
  datacenters = ["dc1"]
  type        = "service"

  group "mongodb" {
    count = 1

    network {
      mode = "host"
      port "mongodb" { static = 27017 }
    }

    volume "mongo_data" {
      type   = "host"
      source = "mongo_data"
    }

    task "mongodb" {
      driver = "docker"

      config {
        image        = "mongo:7.0"
        network_mode = "host"
      }

      volume_mount {
        volume      = "mongo_data"
        destination = "/data/db"
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
        destination = "secrets/mongo.env"
        env         = true
        data        = <<EOF
{{- with secret "secret/data/kalynow/mongodb" }}
MONGO_INITDB_ROOT_USERNAME={{ .Data.data.MONGO_INITDB_ROOT_USERNAME }}
MONGO_INITDB_ROOT_PASSWORD={{ .Data.data.MONGO_INITDB_ROOT_PASSWORD }}
{{- end }}
EOF
      }

      resources {
        cpu    = 300
        memory = 1024
      }

      service {
        name = "mongodb"
        port = "mongodb"

        # Internal service — not exposed via Traefik
        tags = ["traefik.enable=false"]

        check {
          type     = "tcp"
          port     = "mongodb"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}

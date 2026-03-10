job "mongodb" {
  datacenters = ["dc1"]
  type        = "service"

  group "mongodb" {
    count = 1

    network {
      port "mongodb" { static = 27017 }
    }

    volume "mongo_data" {
      type   = "host"
      source = "mongo_data"
    }

    task "mongodb" {
      driver = "docker"

      config {
        image = "mongo:8.0"
        ports = ["mongodb"]
      }

      volume_mount {
        volume      = "mongo_data"
        destination = "/data/db"
      }

      template {
        destination = "secrets/mongo.env"
        env         = true
        data        = <<EOF
MONGO_INITDB_ROOT_USERNAME={{ env "NOMAD_META_mongo_user" | default "kalyNow" }}
MONGO_INITDB_ROOT_PASSWORD={{ env "NOMAD_META_mongo_password" | default "changeme" }}
EOF
      }

      resources {
        cpu    = 300
        memory = 256
      }

      service {
        name = "mongodb"
        port = "mongodb"

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

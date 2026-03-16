variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "mongodb_count" {
  type    = number
  default = 1
}

variable "mongodb_image" {
  type    = string
  default = "mongo:7.0"
}

variable "mongodb_cpu" {
  type    = number
  default = 300
}

variable "mongodb_memory" {
  type    = number
  default = 1024
}

variable "vault_role" {
  type    = string
  default = "nomad-workloads"
}

job "mongodb" {
  datacenters = [var.datacenter]
  type        = "service"

  group "mongodb" {
    count = var.mongodb_count

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
        image        = var.mongodb_image
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
        role        = var.vault_role
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
        cpu    = var.mongodb_cpu
        memory = var.mongodb_memory
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

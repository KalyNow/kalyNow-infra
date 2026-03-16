variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "postgres_count" {
  type    = number
  default = 1
}

variable "postgres_image" {
  type    = string
  default = "postgres:17-alpine"
}

variable "postgres_cpu" {
  type    = number
  default = 300
}

variable "postgres_memory" {
  type    = number
  default = 256
}

variable "vault_role" {
  type    = string
  default = "nomad-workloads"
}

variable "postgres_port" {
  type    = number
  default = 5432
}

job "postgres" {
  datacenters = [var.datacenter]
  type        = "service"

  group "postgres" {
    count = var.postgres_count

    network {
      mode = "host"
      port "postgres" { static = var.postgres_port }
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
        role        = var.vault_role
        change_mode = "restart"
      }

      config {
        image        = var.postgres_image
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
        cpu    = var.postgres_cpu
        memory = var.postgres_memory
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

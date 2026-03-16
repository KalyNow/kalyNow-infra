variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "rustfs_count" {
  type    = number
  default = 1
}

variable "rustfs_image" {
  type    = string
  default = "rustfs/rustfs:1.0.0-alpha.85"
}

variable "rustfs_cpu" {
  type    = number
  default = 300
}

variable "rustfs_memory" {
  type    = number
  default = 256
}

variable "domain" {
  type    = string
  default = "kalynow.mg"
}

variable "vault_role" {
  type    = string
  default = "nomad-workloads"
}

job "rustfs" {
  datacenters = [var.datacenter]
  type        = "service"

  group "rustfs" {
    count = var.rustfs_count

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
        image   = var.rustfs_image
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
        role        = var.vault_role
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
        cpu    = var.rustfs_cpu
        memory = var.rustfs_memory
      }

      service {
        name = "rustfs-api"
        port = "api"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.rustfs.rule=Host(`${var.domain}`) && PathPrefix(`/api/as`)",
          "traefik.http.routers.rustfs.entrypoints=web",
          "traefik.http.routers.rustfs.middlewares=strip-assets-prefix",
          "traefik.http.middlewares.strip-assets-prefix.stripprefix.prefixes=/api/as",
          "traefik.http.services.rustfs-api.loadbalancer.server.port=9000",
        ]

        check {
          type     = "tcp"
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

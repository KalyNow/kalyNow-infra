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

      template {
        destination = "secrets/rustfs.env"
        env         = true
        data        = <<EOF
RUSTFS_ACCESS_KEY={{ env "NOMAD_META_rustfs_access_key" | default "rustfsadmin" }}
RUSTFS_SECRET_KEY={{ env "NOMAD_META_rustfs_secret_key" | default "changeme" }}
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

job "minio" {
  datacenters = ["dc1"]
  type        = "service"

  group "minio" {
    count = 1

    network {
      port "api"     { static = 9000 }
      port "console" { static = 9001 }
    }

    volume "minio_data" {
      type   = "host"
      source = "minio_data"
    }

    task "minio" {
      driver = "docker"

      config {
        image   = "minio/minio:RELEASE.2025-02-28T09-55-16Z"
        ports   = ["api", "console"]
        command = "server"
        args    = ["/data", "--console-address", ":9001"]
      }

      volume_mount {
        volume      = "minio_data"
        destination = "/data"
      }

      template {
        destination = "secrets/minio.env"
        env         = true
        data        = <<EOF
MINIO_ROOT_USER={{ env "NOMAD_META_minio_user" | default "minioadmin" }}
MINIO_ROOT_PASSWORD={{ env "NOMAD_META_minio_password" | default "changeme" }}
EOF
      }

      resources {
        cpu    = 300
        memory = 256
      }

      service {
        name = "minio-api"
        port = "api"

        check {
          type     = "http"
          path     = "/minio/health/live"
          port     = "api"
          interval = "10s"
          timeout  = "2s"
        }
      }

      service {
        name = "minio-console"
        port = "console"
      }
    }
  }
}

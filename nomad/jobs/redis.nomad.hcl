job "redis" {
  datacenters = ["dc1"]
  type        = "service"

  group "redis" {
    count = 1

    network {
      port "redis" { static = 6379 }
    }

    volume "redis_data" {
      type   = "host"
      source = "redis_data"
    }

    task "redis" {
      driver = "docker"

      config {
        image   = "redis:7.4-alpine"
        ports   = ["redis"]
        command = "redis-server"
        args    = ["/usr/local/etc/redis/redis.conf", "--requirepass", "${REDIS_PASSWORD}"]

        volumes = [
          "local/redis.conf:/usr/local/etc/redis/redis.conf",
        ]
      }

      volume_mount {
        volume      = "redis_data"
        destination = "/data"
      }

      template {
        destination = "local/redis.conf"
        data        = <<EOF
bind 0.0.0.0
protected-mode yes
port 6379
save 3600 1
dbfilename dump.rdb
dir /data
maxmemory 256mb
maxmemory-policy allkeys-lru
loglevel notice
EOF
      }

      template {
        destination = "secrets/redis.env"
        env         = true
        data        = <<EOF
REDIS_PASSWORD={{ env "NOMAD_META_redis_password" | default "changeme" }}
EOF
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "redis"
        port = "redis"

        check {
          type     = "tcp"
          port     = "redis"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}

job "kafka" {
  datacenters = ["dc1"]
  type        = "service"

  group "kafka" {
    count = 1

    network {
      port "broker"     { static = 9092 }
      port "controller" { static = 9093 }
    }

    volume "kafka_data" {
      type   = "host"
      source = "kafka_data"
    }

    task "kafka" {
      driver = "docker"

      config {
        image = "apache/kafka:3.9.0"
        ports = ["broker", "controller"]
      }

      volume_mount {
        volume      = "kafka_data"
        destination = "/var/lib/kafka/data"
      }

      env {
        KAFKA_NODE_ID                              = "1"
        KAFKA_PROCESS_ROLES                        = "broker,controller"
        KAFKA_LISTENERS                            = "PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093"
        # Uses Consul service discovery hostname; update if Consul is not available.
        KAFKA_ADVERTISED_LISTENERS                 = "PLAINTEXT://kafka.service.consul:9092"
        KAFKA_CONTROLLER_QUORUM_VOTERS             = "1@localhost:9093"
        KAFKA_CONTROLLER_LISTENER_NAMES            = "CONTROLLER"
        KAFKA_INTER_BROKER_LISTENER_NAME           = "PLAINTEXT"
        KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR     = "1"
        KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR = "1"
        KAFKA_TRANSACTION_STATE_LOG_MIN_ISR        = "1"
        KAFKA_AUTO_CREATE_TOPICS_ENABLE            = "true"
        CLUSTER_ID                                 = "MkU3OEVBNTcwNTJENDM2Qg"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "kafka"
        port = "broker"

        check {
          type     = "tcp"
          port     = "broker"
          interval = "15s"
          timeout  = "5s"
        }
      }
    }
  }
}

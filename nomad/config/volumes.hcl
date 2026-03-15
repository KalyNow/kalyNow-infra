client {
  host_volume "postgres_data" {
    path      = "/opt/nomad/volumes/postgres"
    read_only = false
  }

  host_volume "mongo_data" {
    path      = "/opt/nomad/volumes/mongodb"
    read_only = false
  }

  host_volume "redis_data" {
    path      = "/opt/nomad/volumes/redis"
    read_only = false
  }

  host_volume "rustfs_data" {
    path      = "/opt/nomad/volumes/rustfs"
    read_only = false
  }

  host_volume "kafka_data" {
    path      = "/opt/nomad/volumes/kafka"
    read_only = false
  }

  host_volume "clickhouse_data" {
    path      = "/opt/nomad/volumes/clickhouse"
    read_only = false
  }

  # Persistent Vault file storage
  host_volume "vault_data" {
    path      = "/opt/nomad/volumes/vault"
    read_only = false
  }
}

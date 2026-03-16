# Consul — service discovery & health checking
#
# Runs in -dev mode: single node, in-memory, no persistence needed.
# Nomad registers every job's service{} blocks here automatically.
# Traefik reads this catalog via the consulCatalog provider.
#
# UI:  http://localhost:8500

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "consul_image" {
  type    = string
  default = "hashicorp/consul:1.20"
}

variable "consul_cpu" {
  type    = number
  default = 200
}

variable "consul_memory" {
  type    = number
  default = 128
}

job "consul" {
  datacenters = [var.datacenter]
  type        = "system"

  # Run before everything else
  priority = 90

  group "consul" {

    network {
      port "http" { static = 8500 }
      port "dns"  { static = 8600 }
    }

    task "consul" {
      driver = "docker"

      # Render a startup script that injects the node's primary IP at runtime
      template {
        data        = <<-EOF
          #!/bin/sh
          BIND_IP=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
          exec consul agent -dev -client=0.0.0.0 -bind="$BIND_IP" -ui
          EOF
        destination = "local/start.sh"
        perms       = "755"
      }

      config {
        image        = var.consul_image
        network_mode = "host"
        command      = "/bin/sh"
        args         = ["local/start.sh"]
        volumes      = ["local/start.sh:/local/start.sh"]
      }

      resources {
        cpu    = var.consul_cpu
        memory = var.consul_memory
      }

      # No service{} block here — Consul registers itself
    }
  }
}

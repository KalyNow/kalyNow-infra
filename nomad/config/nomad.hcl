# Nomad agent configuration for local development
# https://developer.hashicorp.com/nomad/docs/configuration

data_dir = "/nomad/data"
log_level = "INFO"
bind_addr = "0.0.0.0"

# Run as both server and client (single-node dev cluster)
server {
  enabled          = true
  bootstrap_expect = 1
}

client {
  enabled = true

  options = {
    "driver.raw_exec.enable" = "1"
  }
}

# Consul integration — Nomad registers every service automatically
consul {
  address = "127.0.0.1:8500"
}

# Vault integration — Workload Identity (JWT)
# Each task gets a short-lived JWT that Vault validates via its JWKS endpoint.
# No static Vault token needed on the Nomad side.
vault {
  enabled = true
  address = "http://127.0.0.1:8200"

  default_identity {
    aud  = ["vault.io"]
    env  = false
    file = true
    ttl  = "1h"
  }
}

# Expose the HTTP API and UI
ports {
  http = 4646
}

# Enable the UI
ui {
  enabled = true
}

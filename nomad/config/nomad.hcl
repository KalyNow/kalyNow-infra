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
  # Use the raw_exec driver so Docker tasks can be submitted from Nomad jobs
  options = {
    "driver.raw_exec.enable" = "1"
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

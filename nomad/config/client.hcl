# Nomad agent config — production client-only node
#
# Use the setup script (recommended) — it injects the IPs automatically:
#   sudo bash scripts/setup_node.sh --advertise-ip <THIS_NODE_IP> --server-ip <SERVER_NODE_IP>
#
# Manual: replace NODE_ADVERTISE_IP and NODE_SERVER_IP before copying.

datacenter = "dc1"
data_dir   = "/opt/nomad"
bind_addr  = "0.0.0.0"
log_level  = "INFO"

client {
  enabled = true

  servers = ["NODE_SERVER_IP:4647"]

  options = {
    "driver.raw_exec.enable" = "1"
  }
}

advertise {
  http = "NODE_ADVERTISE_IP"
  rpc  = "NODE_ADVERTISE_IP"
  serf = "NODE_ADVERTISE_IP"
}

tls {
  http = true
  rpc  = true

  ca_file   = "/etc/nomad.d/nomad-agent-ca.pem"
  cert_file = "/etc/nomad.d/global-client-nomad.pem"
  key_file  = "/etc/nomad.d/global-client-nomad-key.pem"

  verify_server_hostname = true
}

plugin "docker" {
  config {
    allow_privileged = true
  }
}

consul {
  address = "127.0.0.1:8500"
}

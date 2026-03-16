# Nomad agent config — Vault integration (Workload Identity / JWT)
#
# Copy this file to /etc/nomad.d/vault.hcl on every Nomad node and
# restart the Nomad agent:
#   sudo cp nomad/config/vault.hcl /etc/nomad.d/vault.hcl
#   sudo systemctl restart nomad
#
# Without this stanza Nomad is unaware of Vault and every job that
# requests secrets will fail with:
#   "Vault "default" not enabled but used in the job"
#
# The default_identity block makes Nomad automatically generate a
# short-lived JWT (Workload Identity) for each task.  Vault validates
# that JWT via its jwt-nomad auth backend (configured in bootstrap_vault.py).
# No static Vault token is needed on the Nomad side.

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

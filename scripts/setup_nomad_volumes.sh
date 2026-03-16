#!/usr/bin/env bash
set -euo pipefail

# Create local Nomad host volumes with safe defaults and required ownership.
# Run with sudo:
#   sudo bash scripts/setup_nomad_volumes.sh

BASE_DIR="/opt/nomad/volumes"
DEFAULT_MODE="755"

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script must be run as root." >&2
  echo "Use: sudo bash scripts/setup_nomad_volumes.sh" >&2
  exit 1
fi

create_volume() {
  local name="$1"
  local owner="$2"
  local mode="$3"
  local path="${BASE_DIR}/${name}"

  mkdir -p "$path"
  chown -R "$owner" "$path"
  chmod "$mode" "$path"
  printf '✓ %-12s %s owner=%s mode=%s\n' "$name" "$path" "$owner" "$mode"
}

echo "Creating Nomad host volumes in ${BASE_DIR}"

# Generic service data volumes
create_volume postgres root:root "$DEFAULT_MODE"
create_volume mongodb root:root "$DEFAULT_MODE"
create_volume rustfs 10001:10001 "$DEFAULT_MODE"
create_volume kafka root:root "$DEFAULT_MODE"
create_volume redis root:root "$DEFAULT_MODE"
create_volume clickhouse root:root "$DEFAULT_MODE"

# Vault needs write access inside the container for /vault/data
# The official image runs as uid/gid 100 in this environment.
create_volume vault 100:100 770

echo
echo "Done."
echo "If you changed nomad/config/volumes.hcl, copy it to /etc/nomad.d/ and restart Nomad."

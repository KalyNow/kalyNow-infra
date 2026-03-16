#!/usr/bin/env bash
# setup_node.sh — Bootstrap a Nomad node (copy configs + create volumes).
#
# Run ONCE on each node before the first deploy. Must be run as root.
#
# Usage:
#   # Server node (hosts Vault + infra jobs):
#   sudo bash scripts/setup_node.sh --advertise-ip <THIS_NODE_IP> --vault-node
#
#   # Client-only node (hosts app services):
#   sudo bash scripts/setup_node.sh --advertise-ip <THIS_NODE_IP> --server-ip <SERVER_NODE_IP>
#
# What this script does:
#   1. Copies nomad/config/vault.hcl   → /etc/nomad.d/vault.hcl   (all nodes)
#   2. Copies nomad/config/volumes.hcl → /etc/nomad.d/volumes.hcl (all nodes)
#   3a. Server node  : copies server.hcl → /etc/nomad.d/server.hcl
#                      injects NODE_ADVERTISE_IP
#   3b. Client node  : copies client.hcl → /etc/nomad.d/client.hcl
#                      injects NODE_ADVERTISE_IP + NODE_SERVER_IP
#   4. Runs setup_nomad_volumes.sh to create /opt/nomad/volumes/* with
#      correct ownership (rustfs → 10001:10001, vault → 100:100, etc.)

set -euo pipefail

ADVERTISE_IP=""
SERVER_IP=""
VAULT_NODE=false
NOMAD_CONF_DIR="/etc/nomad.d"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --advertise-ip)
            ADVERTISE_IP="$2"
            shift 2
            ;;
        --server-ip)
            SERVER_IP="$2"
            shift 2
            ;;
        --vault-node)
            VAULT_NODE=true
            shift
            ;;
        *)
            echo "❌  Unknown argument: $1"
            echo "Usage: sudo bash scripts/setup_node.sh --advertise-ip <IP> [--vault-node] [--server-ip <IP>]"
            exit 1
            ;;
    esac
done

if [[ -z "$ADVERTISE_IP" ]]; then
    echo "❌  --advertise-ip is required."
    exit 1
fi

if [[ "${VAULT_NODE}" == false && -z "$SERVER_IP" ]]; then
    echo "❌  --server-ip is required on client-only nodes."
    echo "Usage: sudo bash scripts/setup_node.sh --advertise-ip <IP> --server-ip <SERVER_IP>"
    exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "❌  This script must be run as root."
    exit 1
fi

NODE_TYPE="client (connects to ${SERVER_IP})"
[[ "${VAULT_NODE}" == true ]] && NODE_TYPE="server + Vault node"

echo ""
echo "🔧  Setting up Nomad node"
echo "    Advertise IP : ${ADVERTISE_IP}"
echo "    Node type    : ${NODE_TYPE}"
echo ""

# ── 1. Create /etc/nomad.d ────────────────────────────────────────────────────
mkdir -p "${NOMAD_CONF_DIR}"
echo "✓  ${NOMAD_CONF_DIR} ready"

# ── 2. vault.hcl — identical on all nodes ────────────────────────────────────
cp "${REPO_ROOT}/nomad/config/vault.hcl" "${NOMAD_CONF_DIR}/vault.hcl"
echo "✓  vault.hcl"

# ── 3. volumes.hcl — identical on all nodes ──────────────────────────────────
cp "${REPO_ROOT}/nomad/config/volumes.hcl" "${NOMAD_CONF_DIR}/volumes.hcl"
echo "✓  volumes.hcl"

# ── 4. Node-specific config ───────────────────────────────────────────────────
if [[ "${VAULT_NODE}" == true ]]; then
    # Server node: server.hcl with NODE_ADVERTISE_IP replaced
    sed "s/NODE_ADVERTISE_IP/${ADVERTISE_IP}/g" \
        "${REPO_ROOT}/nomad/config/server.hcl" \
        > "${NOMAD_CONF_DIR}/server.hcl"
    echo "✓  server.hcl  (advertise=${ADVERTISE_IP}, vault_server=true)"
else
    # Client node: client.hcl with both placeholders replaced
    sed -e "s/NODE_ADVERTISE_IP/${ADVERTISE_IP}/g" \
        -e "s/NODE_SERVER_IP/${SERVER_IP}/g" \
        "${REPO_ROOT}/nomad/config/client.hcl" \
        > "${NOMAD_CONF_DIR}/client.hcl"
    echo "✓  client.hcl  (advertise=${ADVERTISE_IP}, server=${SERVER_IP})"
fi

# ── 5. Create volume directories ─────────────────────────────────────────────
echo ""
echo "📁  Creating Nomad host volumes..."
bash "${SCRIPT_DIR}/setup_nomad_volumes.sh"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✅  Node setup complete."
echo ""
echo "   Restart Nomad to apply the new config:"
echo "     sudo systemctl restart nomad"
echo ""
echo "   Then verify from the server node:"
echo "     nomad node status"
echo "     consul members"
echo ""

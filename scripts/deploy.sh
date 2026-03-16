#!/usr/bin/env bash
# deploy.sh — Deploy one or all Nomad jobs for a given environment.
#
# Usage:
#   ./scripts/deploy.sh local                      # deploy all jobs (local env)
#   ./scripts/deploy.sh prod                       # deploy all jobs (prod env)
#   ./scripts/deploy.sh local traefik              # deploy single job (local env)
#   ./scripts/deploy.sh prod user-service          # deploy single job (prod env)
#   ./scripts/deploy.sh local --restart            # stop all (except consul) then redeploy in order
#
# Deployment order matters for infrastructure jobs:
#   consul → vault → traefik → databases → services → web

set -euo pipefail

# ── Args ─────────────────────────────────────────────────────────────────────
ENV="${1:-local}"
JOB="${2:-}"
RESTART=false

if [[ "$JOB" == "--restart" ]]; then
    RESTART=true
    JOB=""
fi

ENV_DIR="environments/${ENV}/jobs"
JOBS_DIR="nomad/jobs"

if [[ ! -d "$ENV_DIR" ]]; then
    echo "❌  Unknown environment '${ENV}'. Expected directory: ${ENV_DIR}"
    exit 1
fi

run_job() {
    local job="$1"
    local file="${JOBS_DIR}/${job}.nomad.hcl"
    local vars="${ENV_DIR}/${job}.vars"

    if [[ ! -f "$file" ]]; then
        echo "⚠️   Job file not found: ${file} — skipping"
        return
    fi

    if [[ -f "$vars" ]]; then
        echo "🚀  Deploying ${job} (${ENV})..."
        nomad job run -var-file="${vars}" "${file}"
    else
        echo "⚠️   No var-file for ${job} — deploying with defaults"
        nomad job run "${file}"
    fi
}

stop_job() {
    local job="$1"
    if nomad job status "$job" &>/dev/null; then
        echo "🛑  Stopping ${job}..."
        nomad job stop "$job" || true
    else
        echo "   ${job} not running — skipping stop"
    fi
}

# ── Restart mode: stop all (except consul) then redeploy ──────────────────────
if [[ "$RESTART" == true ]]; then
    echo "🔄  Restart mode — environment: ${ENV}"
    echo "    Stopping all jobs except consul..."
    echo ""

    # Stop in reverse deployment order
    stop_job web
    stop_job offer-service
    stop_job user-service
    stop_job rustfs
    stop_job mongodb
    stop_job postgres
    stop_job traefik
    stop_job vault

    echo ""
    echo "⏳  Waiting for jobs to fully stop..."
    sleep 5

    echo ""
    echo "📦  Redeploying all jobs for environment: ${ENV}"
    echo ""

    # Restart vault first and wait for readiness (handled below in the full deploy flow)
    # Fall through to the full ordered deploy — same logic as a fresh deploy
fi

# ── Single job ────────────────────────────────────────────────────────────────
if [[ -n "$JOB" ]]; then
    run_job "$JOB"
    echo "✅  ${JOB} deployed."
    exit 0
fi

# ── All jobs — ordered ────────────────────────────────────────────────────────
if [[ "$RESTART" == true ]]; then
    echo "🔄  Redeploying all jobs for environment: ${ENV}"
else
    echo "📦  Deploying all jobs for environment: ${ENV}"
fi
echo "    Var-files : ${ENV_DIR}/<job>.vars"
echo ""

# Infrastructure first
run_job consul
sleep 3   # Give Consul a moment to be ready

run_job vault

# ── Vault readiness gate ──────────────────────────────────────────────────────
# Wait for the Vault container to be up, then check its status:
#   • If uninitialized → run init + bootstrap (first-time setup)
#   • If sealed        → unseal it
#   • If ready         → continue
echo ""
echo "⏳  Waiting for Vault to be reachable..."
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
for i in $(seq 1 20); do
    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${VAULT_ADDR}/v1/sys/health" || true)
    # 200 = ready, 429 = standby, 473 = performance standby — all usable
    # 501 = not initialized, 503 = sealed — need action
    if [[ "$STATUS_CODE" =~ ^(200|429|473)$ ]]; then
        echo "✅  Vault is ready (HTTP ${STATUS_CODE})."
        break
    elif [[ "$STATUS_CODE" == "501" ]]; then
        echo ""
        echo "🔑  Vault is NOT initialized. Running first-time setup..."
        python3 scripts/bootstrap_vault.py --init --config scripts/config.py
        echo "🔑  Bootstrapping secrets..."
        python3 scripts/bootstrap_vault.py --config scripts/config.py
        echo "✅  Vault initialized and bootstrapped."
        break
    elif [[ "$STATUS_CODE" == "503" ]]; then
        echo ""
        echo "🔒  Vault is SEALED. Unsealing..."
        python3 scripts/bootstrap_vault.py --unseal-only --config scripts/config.py
        echo "✅  Vault unsealed."
        break
    else
        echo "   Attempt ${i}/20 — Vault not reachable yet (HTTP ${STATUS_CODE:-000}), retrying in 3s..."
        sleep 3
    fi
done

# Final check — abort if Vault is still not usable
FINAL_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${VAULT_ADDR}/v1/sys/health" || true)
if [[ ! "$FINAL_CODE" =~ ^(200|429|473)$ ]]; then
    echo ""
    echo "❌  Vault is still not ready after waiting (HTTP ${FINAL_CODE:-000})."
    echo "    Fix Vault manually before deploying the remaining jobs:"
    echo "      Init:    python3 scripts/bootstrap_vault.py --init --config scripts/config.py"
    echo "      Unseal:  python3 scripts/bootstrap_vault.py --unseal-only --config scripts/config.py"
    exit 1
fi
echo ""
# ─────────────────────────────────────────────────────────────────────────────

run_job traefik

# Databases
run_job postgres
run_job mongodb
run_job rustfs

# Application services
run_job user-service
run_job offer-service

# Frontend last
run_job web

echo ""
echo "✅  All jobs deployed for environment: ${ENV}"

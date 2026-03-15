#!/usr/bin/env python3
"""
bootstrap_vault.py
==================
Manages Vault initialization, unsealing, and secret bootstrapping for KalyNow.

Modes
-----
  --init           Initialize Vault (first-time only). Generates root token +
                   unseal keys, saves them to scripts/.vault-init.json, and
                   patches VAULT_TOKEN into config.py automatically.

  --unseal-only    Unseal Vault after a restart (uses .vault-init.json).
                   Run this every time the Vault container restarts.

  (default)        Full bootstrap: enable engines, write policy, configure JWT
                   auth, write all secrets. Requires Vault to be initialized and
                   unsealed. Safe to re-run (idempotent).

  --dry-run        Show what would be written without making changes (default mode only).

Usage
-----
  # First time:
  python3 scripts/bootstrap_vault.py --init --config scripts/config.py
  python3 scripts/bootstrap_vault.py --config scripts/config.py

  # After every restart:
  python3 scripts/bootstrap_vault.py --unseal-only --config scripts/config.py

No third-party dependencies — stdlib only.
"""

import argparse
import importlib.util
import json
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path


# ---------------------------------------------------------------------------
# Config loader
# ---------------------------------------------------------------------------

def load_config(path: str) -> dict:
    """Import a Python config file and return its public variables as a dict."""
    p = Path(path)
    if not p.exists():
        die(f"Config file not found: {path}")
    spec = importlib.util.spec_from_file_location("config", p)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return {k: v for k, v in vars(module).items() if not k.startswith("_")}


def require(cfg: dict, *names: str) -> dict:
    """Return requested keys from config, failing fast if any are missing or empty."""
    result = {}
    missing = []
    for name in names:
        val = cfg.get(name, "")
        if not isinstance(val, str):
            val = str(val)
        val = val.strip()
        if not val:
            missing.append(name)
        else:
            result[name] = val
    if missing:
        die("Missing required config variables:\n  " + "\n  ".join(missing))
    return result


def vault_request(
    method: str,
    url: str,
    token: str,
    payload: dict | None = None,
    allow_no_token: bool = False,
) -> dict:
    """Perform a Vault API call and return the parsed JSON response."""
    data = json.dumps(payload).encode() if payload is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["X-Vault-Token"] = token
    elif not allow_no_token:
        die("No Vault token available. Run --init first or set VAULT_TOKEN in config.py.")
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        # 400 on mounts/auth enable means already enabled — that's fine
        if e.code == 400 and ("path is already in use" in body or "already in use" in body):
            return {"already_enabled": True}
        die(f"Vault API error {e.code} on {method} {url}:\n{body}")


def put_secret(base_url: str, token: str, path: str, data: dict, dry_run: bool) -> None:
    """Write a KV v2 secret at secret/data/<path>."""
    url = f"{base_url}/v1/secret/data/{path}"
    if dry_run:
        keys = list(data.keys())
        print(f"  [dry-run] would write {path}: {keys}")
        return
    result = vault_request("POST", url, token, {"data": data})
    version = result.get("data", {}).get("version", "?")
    print(f"  ✓ {path}  (version {version})")


def die(msg: str) -> None:
    print(f"\n❌  {msg}", file=sys.stderr)
    sys.exit(1)


def ok(msg: str) -> None:
    print(f"  ✓ {msg}")


# ---------------------------------------------------------------------------
# Init helpers
# ---------------------------------------------------------------------------

INIT_FILE = Path(__file__).parent / ".vault-init.json"


def wait_for_vault(base_url: str, timeout: int = 30) -> None:
    """Wait until Vault's HTTP listener is up (any response)."""
    print(f"  Waiting for Vault at {base_url} ...", end="", flush=True)
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            urllib.request.urlopen(f"{base_url}/v1/sys/health?uninitcode=200&sealedcode=200", timeout=2)
            print(" up")
            return
        except Exception:
            print(".", end="", flush=True)
            time.sleep(1)
    print()
    die(f"Vault did not respond within {timeout}s. Is the job running?")


def step_init(base_url: str, config_path: str) -> None:
    """Initialize Vault, save keys/token to .vault-init.json, patch config.py."""
    print("[init] Checking Vault status...")

    wait_for_vault(base_url)

    # Check if already initialized
    status_resp = vault_request("GET", f"{base_url}/v1/sys/init", token="", payload=None, allow_no_token=True)
    if status_resp.get("initialized"):
        print("  Vault is already initialized.")
        if INIT_FILE.exists():
            ok(f"Init file already exists: {INIT_FILE}")
            _patch_config_token(config_path)
        else:
            die(
                f"Vault is initialized but {INIT_FILE} not found.\n"
                "  If you lost the init file, you must unseal manually with your existing keys.\n"
                "  Then set VAULT_TOKEN in config.py to your root token."
            )
        return

    print("[init] Initializing Vault (1 key share for local dev)...")
    result = vault_request(
        "PUT",
        f"{base_url}/v1/sys/init",
        token="",
        payload={"secret_shares": 1, "secret_threshold": 1},
        allow_no_token=True,
    )

    init_data = {
        "unseal_keys_b64": result["keys_base64"],
        "root_token": result["root_token"],
    }

    INIT_FILE.write_text(json.dumps(init_data, indent=2))
    INIT_FILE.chmod(0o600)
    ok(f"Init data saved to {INIT_FILE}  ← keep this file safe!")

    # Unseal immediately
    _do_unseal(base_url, init_data["unseal_keys_b64"])

    # Patch config.py
    _patch_config_token(config_path, init_data["root_token"])

    print("\n  Vault is now initialized, unsealed, and ready for bootstrap.")
    print(f"  Root token has been written to config.py as VAULT_TOKEN.")
    print(f"\n  Next step:\n    python3 scripts/bootstrap_vault.py --config {config_path}\n")


def step_unseal_only(base_url: str) -> None:
    """Unseal Vault using keys from .vault-init.json."""
    print("[unseal] Unsealing Vault...")

    if not INIT_FILE.exists():
        die(
            f"{INIT_FILE} not found.\n"
            "  Run --init first, or manually create the file with your unseal keys."
        )

    wait_for_vault(base_url)

    init_data = json.loads(INIT_FILE.read_text())
    keys = init_data.get("unseal_keys_b64", [])
    if not keys:
        die(f"No unseal keys found in {INIT_FILE}")

    # Check current seal status
    status = vault_request("GET", f"{base_url}/v1/sys/seal-status", token="", allow_no_token=True)
    if not status.get("sealed", True):
        ok("Vault is already unsealed — nothing to do.")
        return

    _do_unseal(base_url, keys)
    print("\n  Vault is unsealed and ready. ✅")


def _do_unseal(base_url: str, keys: list) -> None:
    for key in keys:
        result = vault_request(
            "PUT",
            f"{base_url}/v1/sys/unseal",
            token="",
            payload={"key": key},
            allow_no_token=True,
        )
        if not result.get("sealed", True):
            ok("Vault unsealed")
            return
    die("Failed to unseal Vault — all keys submitted but Vault is still sealed.")


def _patch_config_token(config_path: str, token: str | None = None) -> None:
    """Write/replace VAULT_TOKEN in config.py with the root token."""
    p = Path(config_path)
    if not p.exists():
        return
    if token is None:
        # Already initialized — read from init file
        if INIT_FILE.exists():
            token = json.loads(INIT_FILE.read_text()).get("root_token", "")
        if not token:
            return

    content = p.read_text()
    import re
    patched = re.sub(
        r'^(VAULT_TOKEN\s*=\s*).*$',
        f'VAULT_TOKEN = "{token}"',
        content,
        flags=re.MULTILINE,
    )
    if patched == content and 'VAULT_TOKEN' not in content:
        patched = content + f'\nVAULT_TOKEN = "{token}"\n'
    p.write_text(patched)
    ok(f"VAULT_TOKEN patched in {config_path}")


# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

def step_enable_kv(base_url: str, token: str, dry_run: bool) -> None:
    print("[1/7] Enabling KV v2 secrets engine...")
    if dry_run:
        print("  [dry-run] would enable secret/ (kv-v2)")
        return
    result = vault_request(
        "POST",
        f"{base_url}/v1/sys/mounts/secret",
        token,
        {"type": "kv", "options": {"version": "2"}},
    )
    if result.get("already_enabled"):
        ok("secret/ already enabled (kv-v2)")
    else:
        ok("secret/ (kv-v2)")


def step_policy(base_url: str, token: str, dry_run: bool) -> None:
    print("[2/7] Writing kalynow-services policy...")
    policy = 'path "secret/data/kalynow/*" { capabilities = ["read"] }'
    if dry_run:
        print("  [dry-run] would write policy: kalynow-services")
        return
    vault_request(
        "PUT",
        f"{base_url}/v1/sys/policies/acl/kalynow-services",
        token,
        {"policy": policy},
    )
    ok("policy: kalynow-services")


def step_jwt_auth(base_url: str, token: str, cfg: dict, dry_run: bool) -> None:
    """Enable JWT auth method and create a role for Nomad Workload Identity."""
    nomad_addr = cfg.get("NOMAD_ADDR", "http://127.0.0.1:4646")
    jwks_url = f"{nomad_addr}/.well-known/jwks.json"

    print("[3/7] Enabling JWT auth backend for Nomad Workload Identity...")
    if dry_run:
        print(f"  [dry-run] would enable auth/jwt-nomad with jwks_url={jwks_url}")
        print("  [dry-run] would create role: nomad-workloads")
        return

    # Enable JWT auth method at jwt-nomad (Nomad's default mount path)
    result = vault_request(
        "POST",
        f"{base_url}/v1/sys/auth/jwt-nomad",
        token,
        {"type": "jwt"},
    )
    if result.get("already_enabled"):
        ok("auth/jwt-nomad already enabled")
    else:
        ok("auth/jwt-nomad enabled")

    # Configure JWT auth to use Nomad's JWKS endpoint
    vault_request(
        "POST",
        f"{base_url}/v1/auth/jwt-nomad/config",
        token,
        {
            "jwks_url": jwks_url,
            "jwt_supported_algs": ["RS256", "EdDSA"],
            "default_role": "nomad-workloads",
        },
    )
    ok(f"auth/jwt-nomad config (jwks_url={jwks_url})")

    # Create the nomad-workloads role
    vault_request(
        "POST",
        f"{base_url}/v1/auth/jwt-nomad/role/nomad-workloads",
        token,
        {
            "role_type": "jwt",
            "bound_audiences": ["vault.io"],
            "user_claim": "nomad_job_id",
            "user_claim_json_type": "string",
            "claim_mappings": {
                "nomad_namespace": "nomad_namespace",
                "nomad_job_id": "nomad_job_id",
                "nomad_task": "nomad_task",
            },
            "token_type": "service",
            "token_policies": ["kalynow-services"],
            "token_period": "30m",
            "token_explicit_max_ttl": 0,
        },
    )
    ok("role: nomad-workloads")


def derive_secrets(cfg: dict) -> dict:
    """
    Derive composite secrets (URLs) from individual credentials.
    Explicit values in config take precedence over derived ones.
    """
    pg_user  = cfg["POSTGRES_USER"]
    pg_pass  = cfg["POSTGRES_PASSWORD"]
    pg_host  = cfg.get("POSTGRES_HOST", "127.0.0.1")
    pg_port  = cfg.get("POSTGRES_PORT", "5432")
    pg_db    = cfg.get("USER_SERVICE_DB_NAME") or cfg["POSTGRES_DB"]

    mongo_user = cfg["MONGO_ROOT_USERNAME"]
    mongo_pass = cfg["MONGO_ROOT_PASSWORD"]
    mongo_host = cfg.get("MONGO_HOST", "127.0.0.1")
    mongo_port = cfg.get("MONGO_PORT", "27017")
    mongo_db   = cfg.get("OFFER_SERVICE_DB_NAME") or "kalynow-offer-service"

    rustfs_key    = cfg["RUSTFS_ACCESS_KEY"]
    rustfs_secret = cfg["RUSTFS_SECRET_KEY"]
    rustfs_host   = cfg.get("RUSTFS_HOST", "127.0.0.1")
    rustfs_port   = cfg.get("RUSTFS_PORT", "9000")

    derived = {
        "USER_SERVICE_DATABASE_URL": (
            cfg.get("USER_SERVICE_DATABASE_URL")
            or f"postgresql://{pg_user}:{pg_pass}@{pg_host}:{pg_port}/{pg_db}"
        ),
        "OFFER_SERVICE_MONGODB_URI": (
            cfg.get("OFFER_SERVICE_MONGODB_URI")
            or f"mongodb://{mongo_user}:{mongo_pass}@{mongo_host}:{mongo_port}/{mongo_db}?authSource=admin"
        ),
        "OFFER_SERVICE_RUSTFS_ENDPOINT": (
            cfg.get("OFFER_SERVICE_RUSTFS_ENDPOINT")
            or f"http://{rustfs_host}:{rustfs_port}"
        ),
        "OFFER_SERVICE_RUSTFS_ACCESS_KEY":  cfg.get("OFFER_SERVICE_RUSTFS_ACCESS_KEY") or rustfs_key,
        "OFFER_SERVICE_RUSTFS_SECRET_KEY":  cfg.get("OFFER_SERVICE_RUSTFS_SECRET_KEY") or rustfs_secret,
        "OFFER_SERVICE_RUSTFS_BUCKET":      cfg.get("OFFER_SERVICE_RUSTFS_BUCKET") or "kalynow-assets",
        "OFFER_SERVICE_RUSTFS_REGION":      cfg.get("OFFER_SERVICE_RUSTFS_REGION") or "us-east-1",
    }

    for key, value in derived.items():
        source = "config" if cfg.get(key, "").strip() else "derived"
        print(f"    {key}  ({source})")

    return derived


def step_infra_secrets(base_url: str, token: str, cfg: dict, dry_run: bool) -> None:
    print("[4/7] Writing infra secrets...")
    put_secret(base_url, token, "kalynow/postgres", {
        "POSTGRES_DB":       cfg["POSTGRES_DB"],
        "POSTGRES_USER":     cfg["POSTGRES_USER"],
        "POSTGRES_PASSWORD": cfg["POSTGRES_PASSWORD"],
    }, dry_run)
    put_secret(base_url, token, "kalynow/mongodb", {
        "MONGO_INITDB_ROOT_USERNAME": cfg["MONGO_ROOT_USERNAME"],
        "MONGO_INITDB_ROOT_PASSWORD": cfg["MONGO_ROOT_PASSWORD"],
    }, dry_run)
    put_secret(base_url, token, "kalynow/rustfs", {
        "RUSTFS_ACCESS_KEY": cfg["RUSTFS_ACCESS_KEY"],
        "RUSTFS_SECRET_KEY": cfg["RUSTFS_SECRET_KEY"],
    }, dry_run)


def step_user_service(base_url: str, token: str, derived: dict, cfg: dict, dry_run: bool) -> None:
    print("[5/7] Writing user-service secrets...")
    put_secret(base_url, token, "kalynow/user-service", {
        "DATABASE_URL":   derived["USER_SERVICE_DATABASE_URL"],
        "JWT_SECRET":     cfg["USER_SERVICE_JWT_SECRET"],
        "JWT_EXPIRES_IN": cfg.get("USER_SERVICE_JWT_EXPIRES_IN", "7d"),
    }, dry_run)


def step_offer_service(base_url: str, token: str, derived: dict, dry_run: bool) -> None:
    print("[6/7] Writing offer-service secrets...")
    put_secret(base_url, token, "kalynow/offer-service", {
        "MONGODB_URI":        derived["OFFER_SERVICE_MONGODB_URI"],
        "RUSTFS_ENDPOINT":    derived["OFFER_SERVICE_RUSTFS_ENDPOINT"],
        "RUSTFS_ACCESS_KEY":  derived["OFFER_SERVICE_RUSTFS_ACCESS_KEY"],
        "RUSTFS_SECRET_KEY":  derived["OFFER_SERVICE_RUSTFS_SECRET_KEY"],
        "RUSTFS_BUCKET":      derived["OFFER_SERVICE_RUSTFS_BUCKET"],
        "RUSTFS_REGION":      derived["OFFER_SERVICE_RUSTFS_REGION"],
    }, dry_run)


def step_cleanup_legacy(base_url: str, token: str, dry_run: bool) -> None:
    """Remove legacy token role nomad-cluster (no longer needed with JWT)."""
    print("[7/7] Cleaning up legacy token role...")
    if dry_run:
        print("  [dry-run] would delete auth/token/roles/nomad-cluster")
        return
    try:
        vault_request("DELETE", f"{base_url}/v1/auth/token/roles/nomad-cluster", token)
        ok("deleted legacy role: nomad-cluster")
    except SystemExit:
        ok("legacy role nomad-cluster not found (already clean)")


def step_verify(base_url: str, token: str) -> None:
    print("\nVerifying all secrets...")
    paths = ["kalynow/postgres", "kalynow/mongodb", "kalynow/rustfs",
             "kalynow/user-service", "kalynow/offer-service"]
    for path in paths:
        result = vault_request("GET", f"{base_url}/v1/secret/data/{path}", token)
        keys = list(result.get("data", {}).get("data", {}).keys())
        print(f"  ✓ {path}: {keys}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Bootstrap Vault secrets for KalyNow")
    parser.add_argument(
        "--config", metavar="FILE", default="scripts/config.py",
        help="Path to config.py (default: scripts/config.py)",
    )
    parser.add_argument(
        "--init", action="store_true",
        help="Initialize Vault (first time only). Saves keys to scripts/.vault-init.json.",
    )
    parser.add_argument(
        "--unseal-only", action="store_true",
        help="Unseal Vault using saved keys (run after every restart).",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would be written without making changes (bootstrap mode only).",
    )
    args = parser.parse_args()

    cfg = load_config(args.config)
    base_url = cfg.get("VAULT_ADDR", "http://127.0.0.1:8200").rstrip("/")

    # ── Init mode ──────────────────────────────────────────────────────────────
    if args.init:
        step_init(base_url, args.config)
        return

    # ── Unseal-only mode ───────────────────────────────────────────────────────
    if args.unseal_only:
        step_unseal_only(base_url)
        return

    # ── Full bootstrap mode ────────────────────────────────────────────────────
    require(cfg,
        "VAULT_ADDR", "VAULT_TOKEN",
        "POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD",
        "MONGO_ROOT_USERNAME", "MONGO_ROOT_PASSWORD",
        "RUSTFS_ACCESS_KEY", "RUSTFS_SECRET_KEY",
        "USER_SERVICE_JWT_SECRET",
    )
    token = cfg["VAULT_TOKEN"]

    # Auto-unseal before bootstrapping if keys are available
    if INIT_FILE.exists():
        status = vault_request("GET", f"{base_url}/v1/sys/seal-status", token="", allow_no_token=True)
        if status.get("sealed", False):
            print("Vault is sealed — unsealing before bootstrap...")
            step_unseal_only(base_url)
            print()

    if args.dry_run:
        print("⚠️  DRY-RUN MODE — no changes will be made\n")

    print("[0/7] Deriving composite secrets from credentials...")
    derived = derive_secrets(cfg)
    print()

    step_enable_kv(base_url, token, args.dry_run)
    step_policy(base_url, token, args.dry_run)
    step_jwt_auth(base_url, token, cfg, args.dry_run)
    step_infra_secrets(base_url, token, cfg, args.dry_run)
    step_user_service(base_url, token, derived, cfg, args.dry_run)
    step_offer_service(base_url, token, derived, args.dry_run)
    step_cleanup_legacy(base_url, token, args.dry_run)

    if not args.dry_run:
        step_verify(base_url, token)

    print("\nBootstrap complete ✅")


if __name__ == "__main__":
    main()

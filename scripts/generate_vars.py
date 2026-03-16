#!/usr/bin/env python3
"""
generate_vars.py
================
Generates Nomad var-files for a given environment from config.py.

All infrastructure parameters (ports, images, resources, domain…) live in
config.py — this script is the single point that writes them into the
per-job .vars files consumed by Nomad.

Usage
-----
  python3 scripts/generate_vars.py --env local --config scripts/config.py
  python3 scripts/generate_vars.py --env prod  --config scripts/config.py
  python3 scripts/generate_vars.py --env prod  --config scripts/config.py --dry-run

Called automatically by deploy.sh before running nomad job run.
"""

import argparse
import importlib.util
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Helpers
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


def get(cfg: dict, key: str, default=None):
    """Return config value or default."""
    return cfg.get(key, default)


def die(msg: str) -> None:
    print(f"\n❌  {msg}", file=sys.stderr)
    sys.exit(1)


def hcl_value(v) -> str:
    """Serialize a Python value to HCL literal."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return str(v)
    # string
    return f'"{v}"'


def write_vars(path: Path, variables: dict, dry_run: bool) -> None:
    """Write a .vars file from a dict of variable_name → value."""
    lines = []
    max_key = max((len(k) for k in variables), default=0)
    for key, value in variables.items():
        lines.append(f"{key:<{max_key}} = {hcl_value(value)}\n")

    content = "".join(lines)

    if dry_run:
        print(f"\n  [dry-run] {path}:")
        for line in lines:
            print(f"    {line}", end="")
        return

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    print(f"  ✓ {path}")


# ---------------------------------------------------------------------------
# Per-job var definitions
# ---------------------------------------------------------------------------

def vars_consul(cfg: dict, env: str) -> dict:
    return {
        "datacenter":    get(cfg, "NOMAD_DATACENTER", "dc1"),
        "consul_image":  get(cfg, "CONSUL_IMAGE",  "hashicorp/consul:1.20"),
        "consul_cpu":    get(cfg, "CONSUL_CPU",    300 if env == "prod" else 200),
        "consul_memory": get(cfg, "CONSUL_MEMORY", 256 if env == "prod" else 128),
    }


def vars_vault(cfg: dict, env: str) -> dict:
    return {
        "datacenter":   get(cfg, "NOMAD_DATACENTER", "dc1"),
        "vault_image":  get(cfg, "VAULT_IMAGE",  "hashicorp/vault:1.17"),
        "vault_cpu":    get(cfg, "VAULT_CPU",    300 if env == "prod" else 200),
        "vault_memory": get(cfg, "VAULT_MEMORY", 512 if env == "prod" else 256),
        "domain":       get(cfg, "DOMAIN", "kalynow.mg"),
    }


def vars_traefik(cfg: dict, env: str) -> dict:
    return {
        "datacenter":                  get(cfg, "NOMAD_DATACENTER", "dc1"),
        "traefik_image":               get(cfg, "TRAEFIK_IMAGE", "traefik:v3.3"),
        "traefik_cpu":                 get(cfg, "TRAEFIK_CPU",    300 if env == "prod" else 200),
        "traefik_memory":              get(cfg, "TRAEFIK_MEMORY", 256 if env == "prod" else 128),
        "domain":                      get(cfg, "DOMAIN", "kalynow.mg"),
        "traefik_dashboard_enabled":   get(cfg, "TRAEFIK_DASHBOARD_ENABLED", env != "prod"),
        "traefik_dashboard_subdomain": get(cfg, "TRAEFIK_DASHBOARD_SUBDOMAIN", "traefik"),
        "traefik_http_port":           get(cfg, "TRAEFIK_HTTP_PORT", 80),
        "traefik_dashboard_port":      get(cfg, "TRAEFIK_DASHBOARD_PORT", 8080),
        # True when Traefik is behind nginx (prod) — enables forwardedHeaders
        "traefik_behind_proxy":         get(cfg, "TRAEFIK_BEHIND_PROXY", env == "prod"),
    }


def vars_postgres(cfg: dict, env: str) -> dict:
    return {
        "datacenter":      get(cfg, "NOMAD_DATACENTER", "dc1"),
        "postgres_count":  get(cfg, "POSTGRES_COUNT",  1),
        "postgres_image":  get(cfg, "POSTGRES_IMAGE",  "postgres:17-alpine"),
        "postgres_cpu":    get(cfg, "POSTGRES_CPU",    1000 if env == "prod" else 300),
        "postgres_memory": get(cfg, "POSTGRES_MEMORY", 1024 if env == "prod" else 256),
        "vault_role":      get(cfg, "VAULT_ROLE", "nomad-workloads"),
        "postgres_port":   int(get(cfg, "POSTGRES_PORT", 5432)),
    }


def vars_mongodb(cfg: dict, env: str) -> dict:
    return {
        "datacenter":     get(cfg, "NOMAD_DATACENTER", "dc1"),
        "mongodb_count":  get(cfg, "MONGODB_COUNT",  1),
        "mongodb_image":  get(cfg, "MONGODB_IMAGE",  "mongo:7.0"),
        "mongodb_cpu":    get(cfg, "MONGODB_CPU",    1000 if env == "prod" else 300),
        "mongodb_memory": get(cfg, "MONGODB_MEMORY", 2048 if env == "prod" else 512),
        "vault_role":     get(cfg, "VAULT_ROLE", "nomad-workloads"),
    }


def vars_rustfs(cfg: dict, env: str) -> dict:
    return {
        "datacenter":    get(cfg, "NOMAD_DATACENTER", "dc1"),
        "rustfs_count":  get(cfg, "RUSTFS_COUNT",  1),
        "rustfs_image":  get(cfg, "RUSTFS_IMAGE",  "rustfs/rustfs:1.0.0-alpha.85"),
        "rustfs_cpu":    get(cfg, "RUSTFS_CPU",    500 if env == "prod" else 300),
        "rustfs_memory": get(cfg, "RUSTFS_MEMORY", 512 if env == "prod" else 256),
        "domain":        get(cfg, "DOMAIN", "kalynow.mg"),
        "vault_role":    get(cfg, "VAULT_ROLE", "nomad-workloads"),
    }


def vars_user_service(cfg: dict, env: str) -> dict:
    is_prod = env == "prod"
    return {
        "datacenter":          get(cfg, "NOMAD_DATACENTER", "dc1"),
        "user_service_count":  get(cfg, "USER_SERVICE_COUNT",  2 if is_prod else 1),
        "user_service_image":  get(cfg, "USER_SERVICE_IMAGE",
                                   "kalynow/user-service:latest" if is_prod else "kalynow/user-service:local"),
        "user_service_cpu":    get(cfg, "USER_SERVICE_CPU",    500 if is_prod else 300),
        "user_service_memory": get(cfg, "USER_SERVICE_MEMORY", 512 if is_prod else 256),
        "domain":              get(cfg, "DOMAIN", "kalynow.mg"),
        "vault_role":          get(cfg, "VAULT_ROLE", "nomad-workloads"),
        "force_pull":          get(cfg, "FORCE_PULL", is_prod),
    }


def vars_offer_service(cfg: dict, env: str) -> dict:
    is_prod = env == "prod"
    return {
        "datacenter":           get(cfg, "NOMAD_DATACENTER", "dc1"),
        "offer_service_count":  get(cfg, "OFFER_SERVICE_COUNT",  2 if is_prod else 1),
        "offer_service_image":  get(cfg, "OFFER_SERVICE_IMAGE",
                                    "kalynow/offer-service:latest" if is_prod else "kalynow/offer-service:local"),
        "offer_service_cpu":    get(cfg, "OFFER_SERVICE_CPU",    500 if is_prod else 300),
        "offer_service_memory": get(cfg, "OFFER_SERVICE_MEMORY", 512 if is_prod else 256),
        "domain":               get(cfg, "DOMAIN", "kalynow.mg"),
        "vault_role":           get(cfg, "VAULT_ROLE", "nomad-workloads"),
        "force_pull":           get(cfg, "FORCE_PULL", is_prod),
    }


def vars_web(cfg: dict, env: str) -> dict:
    is_prod = env == "prod"
    return {
        "datacenter": get(cfg, "NOMAD_DATACENTER", "dc1"),
        "web_count":  get(cfg, "WEB_COUNT",  2 if is_prod else 1),
        "web_image":  get(cfg, "WEB_IMAGE",
                          "kalynow/web:latest" if is_prod else "kalynow/web:local"),
        "web_cpu":    get(cfg, "WEB_CPU",    200 if is_prod else 100),
        "web_memory": get(cfg, "WEB_MEMORY", 128 if is_prod else 64),
        "domain":     get(cfg, "DOMAIN", "kalynow.mg"),
        "force_pull": get(cfg, "FORCE_PULL", is_prod),
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

JOBS = {
    "consul":        vars_consul,
    "vault":         vars_vault,
    "traefik":       vars_traefik,
    "postgres":      vars_postgres,
    "mongodb":       vars_mongodb,
    "rustfs":        vars_rustfs,
    "user-service":  vars_user_service,
    "offer-service": vars_offer_service,
    "web":           vars_web,
}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate Nomad var-files from config.py"
    )
    parser.add_argument(
        "--env", required=True, choices=["local", "prod"],
        help="Target environment",
    )
    parser.add_argument(
        "--config", default="scripts/config.py",
        help="Path to config.py (default: scripts/config.py)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print what would be written without creating files",
    )
    parser.add_argument(
        "--job", default=None,
        help="Generate vars for a single job only",
    )
    args = parser.parse_args()

    cfg = load_config(args.config)
    env = args.env
    out_dir = Path(f"environments/{env}/jobs")

    if args.dry_run:
        print(f"⚠️  DRY-RUN — no files will be written\n")

    print(f"Generating var-files for environment: {env}")
    print(f"Output directory: {out_dir}/\n")

    jobs_to_run = {args.job: JOBS[args.job]} if args.job else JOBS

    if args.job and args.job not in JOBS:
        die(f"Unknown job '{args.job}'. Available: {', '.join(JOBS)}")

    for job_name, vars_fn in jobs_to_run.items():
        variables = vars_fn(cfg, env)
        path = out_dir / f"{job_name}.vars"
        write_vars(path, variables, args.dry_run)

    if not args.dry_run:
        print(f"\n✅  {len(jobs_to_run)} var-file(s) written to {out_dir}/")


if __name__ == "__main__":
    main()

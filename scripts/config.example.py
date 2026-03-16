"""
config.example.py
=================
Configuration template for bootstrap_vault.py.

1. Copy:   cp scripts/config.example.py scripts/config.py
2. Fill in values below
3. Run:    python3 scripts/bootstrap_vault.py --config scripts/config.py

The script derives all composite URLs automatically from credentials.
Override any derived value by setting the optional fields explicitly.

⚠️  Never commit config.py to git  (it's in .gitignore).
Remove config.py after use, or keep it safe if you need it for future reference.
"""

# ── Vault ─────────────────────────────────────────────────────────────────────
VAULT_ADDR  = "http://127.0.0.1:8200"
# Leave empty — `--init` will generate a root token and fill this in automatically.
# Do NOT set this to "root" (that was the old dev-mode token).
VAULT_TOKEN = ""

# ── Nomad (used to derive JWKS URL for Vault JWT auth) ────────────────────────
NOMAD_ADDR  = "http://127.0.0.1:4646"

# ── PostgreSQL ────────────────────────────────────────────────────────────────
POSTGRES_DB       = ""
POSTGRES_USER     = ""
POSTGRES_PASSWORD = ""

# ── MongoDB ───────────────────────────────────────────────────────────────────
MONGO_ROOT_USERNAME = ""
MONGO_ROOT_PASSWORD = ""

# ── RustFS ────────────────────────────────────────────────────────────────────
RUSTFS_ACCESS_KEY = ""
RUSTFS_SECRET_KEY = ""

# ── user-service ──────────────────────────────────────────────────────────────
USER_SERVICE_JWT_SECRET     = ""
USER_SERVICE_JWT_EXPIRES_IN = "7d"

# ── OPTIONAL: override hosts / ports (defaults to localhost) ──────────────────
POSTGRES_HOST         = "127.0.0.1"
POSTGRES_PORT         = "5432"
USER_SERVICE_DB_NAME  = ""        # defaults to POSTGRES_DB if empty

MONGO_HOST            = "127.0.0.1"
MONGO_PORT            = "27017"
OFFER_SERVICE_DB_NAME = "kalynow-offer-service"

RUSTFS_HOST                  = "127.0.0.1"
RUSTFS_PORT                  = "9000"
OFFER_SERVICE_RUSTFS_BUCKET  = "kalynow-assets"
OFFER_SERVICE_RUSTFS_REGION  = "us-east-1"

# ── OPTIONAL: override full URLs (derived automatically if left empty) ─────────
USER_SERVICE_DATABASE_URL    = ""   # postgresql://user:pass@host:port/db
OFFER_SERVICE_MONGODB_URI    = ""   # mongodb://user:pass@host:port/db?authSource=admin
OFFER_SERVICE_RUSTFS_ENDPOINT = ""  # http://host:port
# ──────────────────────────────────────────────────────────────────────────────
# NOMAD INFRASTRUCTURE
# Used by generate_vars.py to write environments/<env>/jobs/*.vars
# Defaults are for local dev. Override here for prod/preprod.
# ──────────────────────────────────────────────────────────────────────────────

# ── Global ───────────────────────────────────────────────────────────────────────
NOMAD_DATACENTER = "dc1"
DOMAIN           = "kalynow.mg"
VAULT_ROLE       = "nomad-workloads"
FORCE_PULL       = False   # True in prod (always pull latest image)

# ── Traefik ───────────────────────────────────────────────────────────────────
TRAEFIK_IMAGE               = "traefik:v3.3"
TRAEFIK_CPU                 = 200
TRAEFIK_MEMORY              = 128
TRAEFIK_DASHBOARD_ENABLED   = True
TRAEFIK_DASHBOARD_SUBDOMAIN = "traefik"
TRAEFIK_HTTP_PORT           = 80      # Set to 8888 if behind nginx on prod
TRAEFIK_DASHBOARD_PORT      = 8080

# ── PostgreSQL ───────────────────────────────────────────────────────────────────
# POSTGRES_HOST / POSTGRES_PORT also drive the DATABASE_URL stored in Vault
POSTGRES_IMAGE  = "postgres:17-alpine"
POSTGRES_COUNT  = 1
POSTGRES_CPU    = 300
POSTGRES_MEMORY = 256
# POSTGRES_HOST and POSTGRES_PORT are already declared above (connection section)
# They are reused here: POSTGRES_PORT drives both the container port AND the DATABASE_URL

# ── MongoDB ─────────────────────────────────────────────────────────────────────
MONGODB_IMAGE  = "mongo:7.0"
MONGODB_COUNT  = 1
MONGODB_CPU    = 300
MONGODB_MEMORY = 512

# ── RustFS ──────────────────────────────────────────────────────────────────────
RUSTFS_IMAGE  = "rustfs/rustfs:1.0.0-alpha.85"
RUSTFS_COUNT  = 1
RUSTFS_CPU    = 300
RUSTFS_MEMORY = 256

# ── Application services ─────────────────────────────────────────────────────────
USER_SERVICE_IMAGE  = "kalynow/user-service:local"
USER_SERVICE_COUNT  = 1
USER_SERVICE_CPU    = 300
USER_SERVICE_MEMORY = 256

OFFER_SERVICE_IMAGE  = "kalynow/offer-service:local"
OFFER_SERVICE_COUNT  = 1
OFFER_SERVICE_CPU    = 300
OFFER_SERVICE_MEMORY = 256

WEB_IMAGE  = "kalynow/web:local"
WEB_COUNT  = 1
WEB_CPU    = 100
WEB_MEMORY = 64

# ── Consul / Vault (infra images) ───────────────────────────────────────────────
CONSUL_IMAGE  = "hashicorp/consul:1.20"
CONSUL_CPU    = 200
CONSUL_MEMORY = 128

VAULT_IMAGE  = "hashicorp/vault:1.17"
VAULT_CPU    = 200
VAULT_MEMORY = 256
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

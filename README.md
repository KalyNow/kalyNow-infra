# kalyNow-infra

Minimal infrastructure repository for the kalyNow microservices platform.

## Services

| Service | Description | Local Port(s) |
|---------|-------------|---------------|
| [Traefik](https://traefik.io/) | API Gateway / Reverse Proxy | 80 (HTTP), 8080 (Dashboard) |
| [Kafka](https://kafka.apache.org/) | Event streaming (KRaft mode) | 9092 |
| [Redis](https://redis.io/) | In-memory cache / message broker | 6379 |
| [PostgreSQL](https://www.postgresql.org/) | Relational database | 5432 |
| [MongoDB](https://www.mongodb.com/) | Document database | 27017 |
| [MinIO](https://min.io/) | S3-compatible object storage | 9000 (API), 9001 (Console) |
| [ClickHouse](https://clickhouse.com/) | Analytical database | 8123 (HTTP), 9004 (Native) |
| [Nomad](https://www.nomadproject.io/) | Workload orchestrator | 4646 |

## Repository Layout

```
kalyNow-infra/
├── docker-compose.yml          # Local development stack
├── .env.example                # Environment variable template
├── traefik/
│   └── traefik.yml             # Traefik static configuration
├── config/
│   ├── redis/
│   │   └── redis.conf          # Redis configuration
│   └── clickhouse/
│       └── users.xml           # ClickHouse user configuration
└── nomad/
    ├── config/
    │   └── nomad.hcl           # Nomad agent configuration
    └── jobs/
        ├── traefik.nomad.hcl
        ├── kafka.nomad.hcl
        ├── redis.nomad.hcl
        ├── postgres.nomad.hcl
        ├── mongodb.nomad.hcl
        ├── minio.nomad.hcl
        └── clickhouse.nomad.hcl
```

## Quick Start (Docker Compose)

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) ≥ 24
- [Docker Compose](https://docs.docker.com/compose/) v2

### 1. Configure environment variables

```bash
cp .env.example .env
# Edit .env and set secure passwords
```

### 2. Start all services

```bash
docker compose up -d
```

### 3. Verify services

```bash
docker compose ps
```

### 4. Stop all services

```bash
docker compose down
```

To also remove all persistent volumes:

```bash
docker compose down -v
```

## Service UIs (local)

| Service | URL |
|---------|-----|
| Traefik Dashboard | <http://localhost:8080> or <http://traefik.localhost> |
| MinIO Console | <http://localhost:9001> or <http://minio.localhost> |
| Nomad UI | <http://localhost:4646> or <http://nomad.localhost> |

## Nomad Jobs

The `nomad/jobs/` directory contains HCL job definitions for deploying each
service via Nomad. These are designed for use with the Nomad agent started by
`docker compose`.

### Submit a job

```bash
# Ensure Nomad is running
export NOMAD_ADDR=http://localhost:4646

# Submit a job (example: PostgreSQL)
nomad job run nomad/jobs/postgres.nomad.hcl
```

### Check job status

```bash
nomad status postgres
```

## Notes

- This setup is intended for **local development only**. Do not use it in production without additional hardening (TLS, secrets management, network policies, etc.).
- Default passwords are defined in `.env.example`. Always change them before starting services.
- Kafka runs in KRaft mode (no ZooKeeper required).

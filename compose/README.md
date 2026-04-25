# Dev Compose

Single-host development stack. No Swarm, no VMs — just Docker.

## Prerequisites

- Docker Desktop (or Docker Engine + Compose plugin)
- `kong/kong.yml` present at repo root (it is — see Phase 5)

## Usage

```bash
# 1. Copy and fill in secrets
cp .env.example .env

# 2. Start all services
docker compose -f docker-compose.dev.yml up -d

# 3. Check everything is healthy
docker compose -f docker-compose.dev.yml ps

# Kong proxy is at http://localhost:8000
# Kong admin API is at http://localhost:8001
# pgAdmin is at http://localhost:5050
# Prometheus is at http://localhost:9090
# Grafana is at http://localhost:3000 (admin / $GRAFANA_ADMIN_PASSWORD)
```

## View logs

```bash
# All services
docker compose -f docker-compose.dev.yml logs -f

# Single service
docker compose -f docker-compose.dev.yml logs -f auth-service
```

## Wipe everything (including volumes)

```bash
docker compose -f docker-compose.dev.yml down -v
```

## Notes

- Services use Spring Boot startup retry — if a DB isn't ready, the service retries automatically.
- Override image versions via `AUTH_IMAGE_TAG`, `BUSINESS_IMAGE_TAG`, `DATA_IMAGE_TAG` in `.env`.
- The Grafana admin password defaults to `admin` if `GRAFANA_ADMIN_PASSWORD` is not set — always set it in `.env`.

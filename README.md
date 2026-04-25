# TrackIT Infrastructure

[![Lint Compose](https://github.com/IDP-proiect6767/trackIT-infrastructure/actions/workflows/lint-compose.yml/badge.svg)](https://github.com/IDP-proiect6767/trackIT-infrastructure/actions/workflows/lint-compose.yml)
[![Kong Validate](https://github.com/IDP-proiect6767/trackIT-infrastructure/actions/workflows/kong-validate.yml/badge.svg)](https://github.com/IDP-proiect6767/trackIT-infrastructure/actions/workflows/kong-validate.yml)
[![ShellCheck](https://github.com/IDP-proiect6767/trackIT-infrastructure/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/IDP-proiect6767/trackIT-infrastructure/actions/workflows/shellcheck.yml)

Infrastructure-as-code for the **TrackIT** cloud-native fitness platform. This repo is the single home for everything that wires the TrackIT microservices into a running system: Docker Swarm cluster provisioning, Kong API Gateway config, monitoring (Prometheus + Grafana), CI/CD, and operational runbooks.

---

## Architecture

![Architecture Diagram](docs/images/architecture-diagram.png)

> Full description in [docs/architecture.md](docs/architecture.md).

**Cluster:** Docker Swarm — 1 Manager + 2 Workers (local Multipass VMs).  
**Gateway:** Kong 3.x OSS, DB-less mode.  
**Networks:** `frontend-net`, `backend-net`, `db-net`, `monitoring-net`.

---

## Service Repos & Images

| Service | Repo | Docker Hub |
|---|---|---|
| Auth Service | [trackIT-auth-service](https://github.com/IDP-proiect6767/trackIT-auth-service) | `florinionita/trackit-auth-service` |
| Business Logic Service | [trackIT-business-logic-service](https://github.com/IDP-proiect6767/trackIT-business-logic-service) | `florinionita/trackit-business-logic-service` |
| Data Service | [trackIT-data-service](https://github.com/IDP-proiect6767/trackIT-data-service) | `florinionita/trackit-data-service` |

---

## Quick Starts

### 1 — Just run the app (single-host, no Swarm)

```bash
cd compose
cp .env.example .env          # fill in passwords
docker compose -f docker-compose.dev.yml up -d
# Kong proxy at http://localhost:8000
```

### 2 — Full Swarm cluster

See the full step-by-step path in [docs/runbook.md](docs/runbook.md).

```bash
# With a working cluster already up and networks created:
cp .env.example stacks/.env   # fill in passwords
bash stacks/deploy-trackit.sh
bash stacks/deploy-monitoring.sh
bash stacks/deploy-portainer.sh
bash stacks/deploy-pgadmin.sh
```

### 3 — Provision VMs from scratch

```bash
bash multipass/launch-cluster.sh
bash swarm/swarm-init.sh
bash swarm/join-workers.sh
bash swarm/label-nodes.sh
bash swarm/create-networks.sh
# then follow Quick Start 2 above
```

---

## Repo Layout

```
trackIT-infrastructure/
├── .env.example               # all secret placeholders
├── multipass/                 # VM provisioning (Multipass)
├── swarm/                     # Swarm init, labels, networks, teardown
├── compose/                   # Single-host dev compose
├── stacks/                    # Swarm stack files + deploy scripts
├── kong/                      # Kong declarative config
├── prometheus/                # Prometheus scrape config
├── grafana/                   # Grafana provisioning
├── pgadmin/                   # pgAdmin server pre-registration
├── scripts/                   # Smoke test + utilities
├── docs/                      # Architecture + runbook
└── .github/workflows/         # CI: lint, validate, shellcheck
```

---

## Configuration Reference

| Variable | Default | Used in |
|---|---|---|
| `AUTH_DB_USER` | `auth_user` | auth-db, auth-service |
| `AUTH_DB_PASSWORD` | *(required)* | auth-db, auth-service |
| `AUTH_DB_NAME` | `auth_db` | auth-db, auth-service |
| `DATA_DB_USER` | `data_user` | data-db, data-service |
| `DATA_DB_PASSWORD` | *(required)* | data-db, data-service |
| `DATA_DB_NAME` | `data_db` | data-db, data-service |
| `AUTH_JWT_SECRET` | *(required)* | auth-service |
| `PGADMIN_DEFAULT_EMAIL` | `admin@trackit.local` | pgadmin |
| `PGADMIN_DEFAULT_PASSWORD` | *(required)* | pgadmin |
| `GRAFANA_ADMIN_PASSWORD` | *(required)* | grafana |
| `AUTH_IMAGE_TAG` | `latest` | compose, stacks |
| `BUSINESS_IMAGE_TAG` | `latest` | compose, stacks |
| `DATA_IMAGE_TAG` | `latest` | compose, stacks |

---

## Known Limitations / Out of Scope

- **TLS/HTTPS** — Kong serves HTTP only. See `docs/runbook.md` for upgrade path.
- **Production secrets** — Currently `.env` files. Migrate to Docker Swarm secrets for real deployments.
- **HA databases** — Single-node Postgres, no replication.
- **Log aggregation** — Logs via `docker service logs`. Loki is the natural extension.
- **Alerting** — Prometheus scrapes but doesn't alert. Alertmanager is the next phase.
- **Per-service dashboards** — Mihai's responsibility; drop `.json` files into `grafana/dashboards/`.

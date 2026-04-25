# TrackIT — Architecture

## Overview

TrackIT is a cloud-native fitness platform composed of three application microservices, two PostgreSQL databases, an API gateway, and an observability stack. Everything runs on a three-node Docker Swarm cluster provisioned as local Multipass VMs.

```
Internet
    │
    ▼
 Kong (8000)                   ← Manager node
    │  frontend-net
    ├──────────────► Auth Service (8081)        ← Worker 1
    │                    │ db-net
    │                    └──► auth-db (5432)    ← Worker 1
    │
    └──────────────► Business Logic Service (8082)  ← Worker 2
                         │ backend-net
                         └──► Data Service (8083)   ← Worker 2
                                   │ db-net
                                   └──► data-db (5432) ← Worker 2

monitoring-net (overlay, all services + Prometheus + Grafana)
```

![Architecture Diagram](images/architecture-diagram.png)

---

## Networks

Four overlay networks isolate concerns. A service joins only the networks it needs (least-privilege networking).

| Network          | Members                                                                 | Purpose |
|------------------|-------------------------------------------------------------------------|---------|
| `frontend-net`   | Kong, Auth Service, Business Logic Service                              | External traffic ingress; Kong routes to services |
| `backend-net`    | Business Logic Service, Data Service                                    | Internal business → data calls (not reachable from outside) |
| `db-net`         | Auth Service, Data Service, `auth-db`, `data-db`, pgAdmin               | Database access only |
| `monitoring-net` | Prometheus, Grafana, Portainer, all services with `/actuator/prometheus` | Observability scraping |

### Security consequences

- **Data Service is NOT on `frontend-net`** — cannot be reached from the internet even if Kong is misconfigured.
- **Kong is NOT on `db-net`** — cannot reach Postgres directly.
- **Auth Service is on `frontend-net`** (Kong routes `/api/v1/auth/*`) and `db-net` (its own DB).
- **Business Logic is on `frontend-net`** + `backend-net` + `monitoring-net`. Not on `db-net`.

---

## Cluster Placement

Each service is pinned to a node via Swarm placement constraints set in Phase 1 (`swarm/label-nodes.sh`).

| Service                | Node      | Constraint                        |
|------------------------|-----------|-----------------------------------|
| Kong                   | Manager   | `node.role == manager`            |
| Portainer              | Manager   | `node.role == manager`            |
| pgAdmin                | Manager   | `node.role == manager`            |
| Prometheus             | Manager   | `node.role == manager`            |
| Grafana                | Manager   | `node.role == manager`            |
| Auth Service           | Worker 1  | `node.labels.role == auth`        |
| `auth-db` (Postgres)   | Worker 1  | `node.labels.role == auth`        |
| Business Logic Service | Worker 2  | `node.labels.role == app`         |
| Data Service           | Worker 2  | `node.labels.role == app`         |
| `data-db` (Postgres)   | Worker 2  | `node.labels.role == app`         |

---

## Request Flow Examples

### Login: `POST /api/v1/auth/login`

```
Client → Kong :8000 (frontend-net)
    Kong matches route /api/v1/auth → auth-service:8081 (frontend-net)
    Auth Service validates credentials against auth-db:5432 (db-net)
    Auth Service returns JWT
Kong returns 200 + JWT to client
```

### Fetch workouts: `GET /api/v1/workouts` (with Bearer token)

```
Client → Kong :8000 (frontend-net)
    Kong matches route /api/v1/workouts → business-logic-service:8082 (frontend-net)
    Business Logic calls auth-service:8081/api/v1/auth/validate (frontend-net, direct — not through Kong)
    Auth Service validates token → returns {valid: true, userId: ...}
    Business Logic calls data-service:8083/api/v1/workouts (backend-net)
    Data Service queries data-db:5432 (db-net)
    Data Service returns workout list
Business Logic returns 200 + workouts to Kong → to client
```

---

## Security Boundaries

| Boundary | Enforcement |
|---|---|
| Data Service unreachable from internet | Not on `frontend-net` → no path from Kong |
| DBs unreachable from Kong | Kong not on `db-net` |
| Admin role enforcement | Auth Service `@PreAuthorize("hasRole('ADMIN')")` — Kong just routes |
| Rate limiting | Kong plugins: 100 req/min global, 20 req/min on auth routes |
| CORS | Kong cors plugin — `*` origins for demo |

> **Note:** `/api/v1/auth/validate` is intentionally public — services call it directly for JWT validation over `frontend-net`.

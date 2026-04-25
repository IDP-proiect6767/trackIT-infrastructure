# TrackIT Infrastructure — Full Implementation Plan

> **For:** Claude Code agent. Implement **one phase at a time**. After each phase: stop, summarize what was done, update `[Unreleased]` in `CHANGELOG.md`, and wait for the user to review/commit before continuing to the next phase. Do not skip ahead.

## Project context

- **Repo:** `trackIT-infrastructure`. The single home for everything that wires the TrackIT microservices into a running system.
- **Owner:** Florin (Auth Service author + cluster/gateway/CI owner per the project document).
- **Cluster:** Docker Swarm — **1 Manager + 2 Workers**, running as **local Multipass VMs** on the developer's machine. The plan is host-agnostic where reasonable so the same files run on cloud VMs (DigitalOcean, GCP) with minor changes.
- **Gateway:** Kong 3.x OSS, **DB-less mode** with declarative config (`kong.yml`).
- **Networks:** four Docker overlay networks — `frontend-net`, `backend-net`, `db-net`, `monitoring-net`. See "Network topology" below.
- **Services orchestrated:** Kong, Auth Service, Business Logic Service, Data Service, two PostgreSQL instances (`auth_db`, `data_db`), pgAdmin, Prometheus, Grafana, Portainer.
- **Monitoring scope (for this repo):** Prometheus scrape config, Grafana datasource provisioning, container deployment of both. Per-service dashboards are Mihai's responsibility — this repo provides the platform he plugs into.
- **HTTP only** for the demo. TLS / Let's Encrypt is explicitly out of scope (see "Out of scope" at the end).

## Conventions

- **Commits:** Conventional Commits (`feat:`, `chore:`, `docs:`, `ci:`, `build:`, `fix:`).
- **Branching:** Work on `main`. At least one commit per phase.
- **Shell scripts:** POSIX-compatible bash, `set -euo pipefail` at the top of every non-trivial script. Make them idempotent where possible (re-running shouldn't break a working cluster).
- **Filenames:** lowercase-hyphenated (`kong.yml`, `swarm-init.sh`, `stack-trackit.yml`).
- **Secrets:** `.env` files for local dev (gitignored). Docker secrets / Swarm secrets for production paths. Never commit real secrets — only `.env.example` files with placeholders.
- **Stack files:** Compose v3.8+ syntax. Use `deploy:` blocks (Swarm-native) instead of `docker-compose`-only directives.

## Network topology

Four overlay networks isolating concerns. A service joins only the networks it needs.

| Network          | Members                                                                  | Purpose |
|------------------|--------------------------------------------------------------------------|---------|
| `frontend-net`   | Kong, Auth Service, Business Logic Service                               | External traffic ingress + JWT validation reachability |
| `backend-net`    | Business Logic Service, Data Service                                     | Internal business → data calls |
| `db-net`         | Auth Service, Data Service, `auth-db`, `data-db`, pgAdmin                | Database access only |
| `monitoring-net` | Prometheus, Grafana, Portainer + every service exposing `/actuator/prometheus` | Observability scraping |

**Key consequences:**
- Data Service is **not** on `frontend-net` → cannot be reached from the outside even if Kong is misconfigured.
- Kong is **not** on `db-net` → cannot reach Postgres directly.
- Auth Service is on `frontend-net` (so Kong can route `/api/v1/auth/*`) and on `db-net` (its own DB).
- Business Logic is on `frontend-net` (so Kong can route business endpoints), `backend-net` (to call Data Service), and `monitoring-net`. **Not** on `db-net`.

## Cluster placement

Each service is pinned to a node via labels (set in Phase 1).

| Service               | Node       | Constraint                          |
|-----------------------|------------|-------------------------------------|
| Kong                  | Manager    | `node.role == manager`              |
| Portainer             | Manager    | `node.role == manager`              |
| pgAdmin               | Manager    | `node.role == manager`              |
| Prometheus            | Manager    | `node.role == manager`              |
| Grafana               | Manager    | `node.role == manager`              |
| Auth Service          | Worker 1   | `node.labels.role == auth`          |
| `auth-db` (Postgres)  | Worker 1   | `node.labels.role == auth`          |
| Business Logic Service| Worker 2   | `node.labels.role == app`           |
| Data Service          | Worker 2   | `node.labels.role == app`           |
| `data-db` (Postgres)  | Worker 2   | `node.labels.role == app`           |

## Repo layout (target state at end of plan)

```
trackIT-infrastructure/
├── README.md
├── CHANGELOG.md
├── IMPLEMENTATION_PLAN.md
├── .env.example
├── .gitignore
├── docs/
│   ├── architecture.md
│   ├── runbook.md
│   └── images/
│       └── architecture-diagram.png   # copy from project doc
├── multipass/
│   ├── cloud-init.yaml
│   ├── launch-cluster.sh
│   ├── destroy-cluster.sh
│   └── ssh-into.sh
├── swarm/
│   ├── swarm-init.sh
│   ├── join-workers.sh
│   ├── label-nodes.sh
│   └── teardown.sh
├── compose/
│   ├── docker-compose.dev.yml         # single-host dev stack (no Swarm)
│   └── .env.example
├── stacks/
│   ├── stack-trackit.yml              # main app stack (Kong + 3 services + DBs)
│   ├── stack-monitoring.yml           # Prometheus + Grafana
│   ├── stack-portainer.yml
│   └── stack-pgadmin.yml
├── kong/
│   ├── kong.yml                       # declarative config
│   └── README.md                      # how to validate/reload
├── prometheus/
│   ├── prometheus.yml
│   └── alerts/                        # empty for now, structure for later
├── grafana/
│   └── provisioning/
│       ├── datasources/
│       │   └── prometheus.yml
│       └── dashboards/
│           └── dashboards.yml         # provisioning config; .json files added by Mihai
├── pgadmin/
│   └── servers.json                   # pre-registered DB connections
└── .github/
    └── workflows/
        ├── lint-compose.yml           # validate compose/stack files on push
        └── kong-validate.yml          # validate kong.yml on push
```

---

## Phase 0 — Repo bootstrap

**Goal:** Empty repo with structure, README skeleton, and changelog.

1. `git init` (if not already), set remote `git@github.com:IDP-proiect6767/trackIT-infrastructure.git`.
2. Create the directory skeleton from "Repo layout" above (empty directories with `.gitkeep` files where needed).
3. `README.md` skeleton:
   - Project title + one-paragraph description ("Infrastructure-as-code for the TrackIT cloud-native fitness platform...").
   - Link to the umbrella project document and the four service repos.
   - **Quick start (placeholder)** — to be filled in incrementally as later phases land.
   - Architecture diagram placeholder (insert in Phase 9).
4. `CHANGELOG.md`: same Keep-a-Changelog format as the Auth Service repo, starting with `## [Unreleased]` and an `### Added` entry for the bootstrap.
5. `.gitignore`:
   ```
   .env
   .env.local
   *.log
   *.pid
   .idea/
   .vscode/
   ```
6. `.env.example` at repo root with placeholders for every secret used across stacks (passwords for both DBs, JWT secret, pgAdmin admin, Grafana admin, Portainer admin). Every variable starts as `change-me`.
7. `IMPLEMENTATION_PLAN.md` = a copy of this file.

**Acceptance:** Repo pushed to GitHub. `tree -L 2` matches the layout above.

---

## Phase 1 — Multipass cluster bring-up

**Goal:** Three reproducible Linux VMs ready for Docker Swarm.

1. `multipass/cloud-init.yaml` — cloud-init manifest used at VM launch:
   - Update apt cache, install `curl`, `ca-certificates`, `gnupg`.
   - Install Docker CE from the official Docker apt repo (script-style: add GPG key, add repo, `apt install docker-ce docker-ce-cli containerd.io`).
   - Add user `ubuntu` to the `docker` group.
   - Enable + start the Docker service.
   - **Do not** init Swarm here — that happens in Phase 2.
2. `multipass/launch-cluster.sh`:
   - Variables: `MANAGER_NAME=trackit-manager`, `WORKER1_NAME=trackit-worker-1`, `WORKER2_NAME=trackit-worker-2`.
   - VM specs: manager 2 CPU / 2 GB RAM / 10 GB disk; workers 2 CPU / 2 GB RAM / 10 GB disk each. (Tweak if the host has more RAM — document.)
   - For each VM: `multipass launch --name <name> --cpus 2 --memory 2G --disk 10G --cloud-init cloud-init.yaml 22.04` (Ubuntu 22.04 LTS).
   - After launch, `multipass exec <name> -- docker --version` to verify Docker is up.
   - Print a summary table: VM name, IP (from `multipass info`), role.
3. `multipass/destroy-cluster.sh`: stops + deletes all three VMs (`multipass delete --purge`).
4. `multipass/ssh-into.sh`: helper — `./ssh-into.sh manager` shells into manager via `multipass shell`.

**Acceptance:**
- `bash multipass/launch-cluster.sh` brings up three VMs in ~3 minutes.
- `multipass exec trackit-manager -- docker info` shows Docker running.
- All three VMs are pingable from each other (verify with `multipass exec trackit-manager -- ping -c1 <worker-ip>`).
- `bash multipass/destroy-cluster.sh` cleanly removes them.

---

## Phase 2 — Docker Swarm initialization

**Goal:** Three-node Swarm with role labels, ready to receive stacks.

1. `swarm/swarm-init.sh`:
   - Run on the manager VM (script handles this via `multipass exec`).
   - `MANAGER_IP=$(multipass info trackit-manager --format json | jq -r '.info["trackit-manager"].ipv4[0]')`.
   - On manager: `docker swarm init --advertise-addr $MANAGER_IP`.
   - Capture the worker join token: `JOIN_TOKEN=$(multipass exec trackit-manager -- docker swarm join-token -q worker)`.
   - Echo manager IP and token into a file `swarm/.swarm-state` (gitignored).
2. `swarm/join-workers.sh`:
   - Reads `swarm/.swarm-state`.
   - For each worker VM: `multipass exec <worker> -- docker swarm join --token $JOIN_TOKEN $MANAGER_IP:2377`.
   - Verify via `multipass exec trackit-manager -- docker node ls` — expect 3 nodes, manager `Leader`, workers `Active`.
3. `swarm/label-nodes.sh`:
   - On manager: apply Swarm node labels matching the Cluster placement table:
     - `docker node update --label-add role=auth trackit-worker-1`
     - `docker node update --label-add role=app trackit-worker-2`
   - The manager is identified by `node.role == manager` (built-in), no extra label needed.
   - Verify: `docker node inspect <name> --format '{{ .Spec.Labels }}'`.
4. `swarm/teardown.sh`:
   - On each worker: `docker swarm leave`.
   - On manager: `docker swarm leave --force`.
   - Removes `swarm/.swarm-state`.
5. `.gitignore` add: `swarm/.swarm-state`.

**Acceptance:**
- Running the three scripts in order leaves a healthy Swarm: `docker node ls` shows 3 ready nodes with correct labels.
- A test service deployed without constraints distributes across nodes; one with `node.labels.role == app` lands only on Worker 2 (verified by `docker service ps`).

---

## Phase 3 — Network creation

**Goal:** The four overlay networks exist, ready for stacks to attach.

1. `swarm/create-networks.sh`:
   - On manager:
     - `docker network create --driver overlay --attachable frontend-net`
     - `docker network create --driver overlay --attachable backend-net`
     - `docker network create --driver overlay --attachable db-net`
     - `docker network create --driver overlay --attachable monitoring-net`
   - `--attachable` lets us run one-off `docker run --network ...` containers for debugging.
   - Idempotent: skip if `docker network inspect <name>` succeeds.
2. Document in `docs/architecture.md` (initial draft): the four networks, who's on each, and the rationale (least privilege).

**Acceptance:** `docker network ls` on manager shows all four overlay networks.

---

## Phase 4 — Single-host dev compose (no Swarm)

**Goal:** A `docker-compose.yml` developers can run on a laptop without setting up VMs at all. Useful for local development and for Mihai while building Business Logic / Data services.

1. `compose/docker-compose.dev.yml` — Compose v3.8, full app stack on a single Docker engine:
   - **Services:** `auth-db`, `data-db`, `auth-service`, `business-logic-service`, `data-service`, `kong`, `pgadmin`, `prometheus`, `grafana`.
   - **No `deploy:` blocks** (this file is for `docker compose up`, not `docker stack deploy`).
   - Use the same image names that prod uses: `florinionita/trackit-auth-service:latest`, etc. Each service can be overridden via `IMAGE_TAG` env var to a specific commit SHA for testing.
   - Networks: define the four networks here too as `bridge` driver (overlay needs Swarm). Same membership rules as prod.
   - Depends-on with healthchecks (Postgres healthcheck `pg_isready`, services use `/actuator/health`).
   - Volumes: named volumes for `auth-db-data`, `data-db-data`, `pgadmin-data`, `prometheus-data`, `grafana-data`.
2. `compose/.env.example`:
   ```
   # Postgres
   AUTH_DB_PASSWORD=change-me
   DATA_DB_PASSWORD=change-me

   # Auth
   AUTH_JWT_SECRET=change-me-change-me-change-me-change-me

   # Admin tools
   PGADMIN_DEFAULT_EMAIL=admin@trackit.local
   PGADMIN_DEFAULT_PASSWORD=change-me
   GRAFANA_ADMIN_PASSWORD=change-me

   # Image overrides (optional; defaults to :latest)
   AUTH_IMAGE_TAG=latest
   BUSINESS_IMAGE_TAG=latest
   DATA_IMAGE_TAG=latest
   ```
3. `compose/README.md`: how to run (`cp .env.example .env && docker compose up -d`), how to view logs, how to wipe (`docker compose down -v`).

**Acceptance:** On a clean Docker installation: `cd compose && cp .env.example .env && docker compose up -d` brings up all services. `curl http://localhost:8000/api/v1/auth/register` (Kong's default proxy port → Auth Service) returns a sensible response (404 or 405 if endpoint not yet routed — the stack itself is healthy).

---

## Phase 5 — Kong API Gateway (DB-less, declarative)

**Goal:** Kong routes external traffic to the right service. One config file, version-controlled.

1. `kong/kong.yml` — declarative config:
   ```yaml
   _format_version: "3.0"
   _transform: true

   services:
     - name: auth-service
       url: http://auth-service:8081
       routes:
         - name: auth-routes
           paths:
             - /api/v1/auth
             - /api/v1/users
             - /api/v1/admin/users
           strip_path: false

     - name: business-logic-service
       url: http://business-logic-service:8082
       routes:
         - name: business-routes
           paths:
             - /api/v1/workouts
             - /api/v1/exercises
             - /api/v1/workout-logs
             - /api/v1/foods
             - /api/v1/meals
             - /api/v1/stats
             - /api/v1/dashboard
             - /api/v1/users/me/goals
           strip_path: false

   plugins:
     # Global rate limit: 100 req/min per IP
     - name: rate-limiting
       config:
         minute: 100
         policy: local
         limit_by: ip
         fault_tolerant: true

     # Tighter rate limit on login/register to slow brute force
     - name: rate-limiting
       route: auth-routes
       config:
         minute: 20
         policy: local
         limit_by: ip

     # CORS for browser clients
     - name: cors
       config:
         origins:
           - "*"
         methods:
           - GET
           - POST
           - PATCH
           - DELETE
           - OPTIONS
         headers:
           - Authorization
           - Content-Type
         credentials: false
         max_age: 3600

     # Request logging (stdout)
     - name: file-log
       config:
         path: /dev/stdout
   ```
2. **Important Kong notes:**
   - `/api/v1/admin/users` is *also* exposed but Kong doesn't enforce role — the Auth Service does that with `@PreAuthorize("hasRole('ADMIN')")`. Kong is just a router.
   - `/api/v1/auth/validate` is public-by-design (Auth Service docs say so), but it's also useful **internally** between services. Business Logic calls it directly via `http://auth-service:8081/api/v1/auth/validate` over `frontend-net`, **not** through Kong. Kong is for external clients only.
3. `kong/README.md`: how to validate the config locally (`docker run --rm -v $(pwd)/kong.yml:/kong.yml kong:3 kong config -c /kong.yml parse /kong.yml`).
4. **Wire Kong into `compose/docker-compose.dev.yml` and the future Swarm stack (Phase 6):**
   - `KONG_DATABASE: "off"` (DB-less mode).
   - `KONG_DECLARATIVE_CONFIG: /kong/kong.yml`
   - Mount `./kong/kong.yml:/kong/kong.yml:ro`.
   - `KONG_PROXY_ACCESS_LOG: /dev/stdout`
   - `KONG_ADMIN_ACCESS_LOG: /dev/stdout`
   - `KONG_PROXY_ERROR_LOG: /dev/stderr`
   - `KONG_ADMIN_ERROR_LOG: /dev/stderr`
   - `KONG_ADMIN_LISTEN: 0.0.0.0:8001` (admin API; bind only to localhost in prod)
   - Ports: `8000:8000` (proxy / public), `8001:8001` (admin — local only).
   - Network: `frontend-net`.

**Acceptance:**
- `kong config parse kong/kong.yml` returns valid.
- After `docker compose up`: `curl -i http://localhost:8000/api/v1/auth/register -X POST -H "Content-Type: application/json" -d '{"username":"test","email":"test@x.io","password":"password123"}'` returns 201 — proving Kong routed to Auth Service.
- `curl http://localhost:8000/api/v1/workouts` (no token) returns 401 from Business Logic — proving Kong routes business traffic too.
- Hammering `/api/v1/auth/login` 25 times in a minute hits the route-level rate limit → 429.

---

## Phase 6 — Swarm stack: TrackIT app

**Goal:** Production stack file deployable via `docker stack deploy`.

1. `stacks/stack-trackit.yml`:
   - Compose v3.8.
   - **Services:**
     - `auth-db` (postgres:16-alpine):
       - Placement: `node.labels.role == auth`.
       - Volume: `auth-db-data`.
       - Network: `db-net`.
       - Env: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB=auth_db`.
       - Healthcheck: `pg_isready -U $POSTGRES_USER`.
     - `data-db` (postgres:16-alpine):
       - Same shape, on Worker 2 (`role=app`).
     - `auth-service` (`florinionita/trackit-auth-service:latest`):
       - Placement: `node.labels.role == auth`.
       - Networks: `frontend-net`, `db-net`, `monitoring-net`.
       - `depends_on` is unsupported in Swarm — rely on Spring Boot's startup retry + healthcheck.
       - Env: `AUTH_DB_URL`, `AUTH_DB_USER`, `AUTH_DB_PASSWORD`, `AUTH_JWT_SECRET`.
       - Healthcheck: `curl -f http://localhost:8081/actuator/health || exit 1`.
       - `deploy.replicas: 1`, `deploy.update_config.parallelism: 1, order: start-first`.
     - `business-logic-service` (`florinionita/trackit-business-logic-service:latest`):
       - Placement: `node.labels.role == app`.
       - Networks: `frontend-net`, `backend-net`, `monitoring-net`.
       - Env: `AUTH_SERVICE_URL=http://auth-service:8081`, `DATA_SERVICE_URL=http://data-service:8083`.
     - `data-service` (`florinionita/trackit-data-service:latest`):
       - Placement: `node.labels.role == app`.
       - Networks: `backend-net`, `db-net`, `monitoring-net`.
       - Env: `DATA_DB_URL`, `DATA_DB_USER`, `DATA_DB_PASSWORD`.
       - **Not** on `frontend-net` — confirmed defense-in-depth.
     - `kong`:
       - Placement: `node.role == manager`.
       - Networks: `frontend-net`, `monitoring-net`.
       - Volume mount: `./kong/kong.yml:/kong/kong.yml:ro`.
       - Ports published: `8000:8000` (proxy). **Admin API not published** in Swarm — use `docker exec` to inspect.
   - **Volumes (top level):** `auth-db-data`, `data-db-data` (driver `local`).
   - **Networks (top level):** all four marked `external: true` — they were created in Phase 3.
   - **Secrets approach:** for the project demo, use env vars from a `.env`-style file passed via `docker stack deploy --compose-file ... -c <env>`. (Swarm `secrets:` is more secure but adds friction; document the upgrade path in `docs/runbook.md`.)
2. `stacks/.env.example` — one of these per stack family.
3. `stacks/deploy-trackit.sh`:
   - Sources `.env`.
   - `docker stack deploy -c stack-trackit.yml trackit`.
   - Wait loop: poll `docker service ls` until all replicas show `1/1`.

**Acceptance:**
- `bash stacks/deploy-trackit.sh` deploys the stack.
- `docker service ls` shows 6 services (4 app + 2 DBs + Kong = 7 actually) all 1/1.
- `docker service ps <svc>` confirms placement (auth services on Worker 1, business+data on Worker 2, Kong on Manager).
- From the host: `curl -i http://<manager-ip>:8000/api/v1/auth/register` works end-to-end.

---

## Phase 7 — Monitoring stack (Prometheus + Grafana)

**Goal:** Prometheus scrapes all three services. Grafana is wired to Prometheus and ready for dashboards (which Mihai owns).

1. `prometheus/prometheus.yml`:
   ```yaml
   global:
     scrape_interval: 15s
     evaluation_interval: 15s

   scrape_configs:
     - job_name: 'auth-service'
       metrics_path: '/actuator/prometheus'
       static_configs:
         - targets: ['auth-service:8081']

     - job_name: 'business-logic-service'
       metrics_path: '/actuator/prometheus'
       static_configs:
         - targets: ['business-logic-service:8082']

     - job_name: 'data-service'
       metrics_path: '/actuator/prometheus'
       static_configs:
         - targets: ['data-service:8083']

     - job_name: 'kong'
       static_configs:
         - targets: ['kong:8001']    # only works if Kong's prometheus plugin is enabled — see note below
   ```
   - **Note on Kong metrics:** add `- name: prometheus` to the global plugins list in `kong/kong.yml`. Kong then exposes `/metrics` on the admin port (8001). Update Phase 5 deliverables when this is added.
2. `grafana/provisioning/datasources/prometheus.yml`:
   ```yaml
   apiVersion: 1
   datasources:
     - name: Prometheus
       type: prometheus
       access: proxy
       url: http://prometheus:9090
       isDefault: true
       editable: false
   ```
3. `grafana/provisioning/dashboards/dashboards.yml`:
   ```yaml
   apiVersion: 1
   providers:
     - name: 'TrackIT'
       orgId: 1
       folder: 'TrackIT'
       type: file
       disableDeletion: false
       editable: true
       options:
         path: /var/lib/grafana/dashboards
   ```
   - Mihai drops `.json` dashboard exports into `grafana/dashboards/` — they're auto-loaded. This repo creates the empty directory with a `.gitkeep`.
4. `stacks/stack-monitoring.yml`:
   - **Prometheus:**
     - Image: `prom/prometheus:v2.x`.
     - Placement: `node.role == manager`.
     - Network: `monitoring-net`.
     - Volume mount: `./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro`.
     - Volume: `prometheus-data:/prometheus`.
     - Ports: `9090:9090` (debug only — close in real deployment).
   - **Grafana:**
     - Image: `grafana/grafana:10.x`.
     - Placement: `node.role == manager`.
     - Network: `monitoring-net`.
     - Volume mounts: `./grafana/provisioning:/etc/grafana/provisioning:ro`, `./grafana/dashboards:/var/lib/grafana/dashboards:ro`.
     - Volume: `grafana-data:/var/lib/grafana`.
     - Env: `GF_SECURITY_ADMIN_PASSWORD`, `GF_USERS_ALLOW_SIGN_UP=false`.
     - Ports: `3000:3000`.
   - Networks: `monitoring-net` external.
5. `stacks/deploy-monitoring.sh`: same pattern as `deploy-trackit.sh`.

**Acceptance:**
- `bash stacks/deploy-monitoring.sh`.
- `curl http://<manager-ip>:9090/api/v1/targets` — all 4 jobs show `state: up`.
- Grafana at `http://<manager-ip>:3000` (login `admin` / env password) → Prometheus datasource connected (Configuration → Data Sources → green check).
- Drop a sample dashboard JSON into `grafana/dashboards/` → it appears in the TrackIT folder after Grafana restart.

---

## Phase 8 — Portainer + pgAdmin

**Goal:** Two operator UIs for cluster + DB management.

1. `stacks/stack-portainer.yml`:
   - Image: `portainer/portainer-ce:latest`.
   - Placement: `node.role == manager`.
   - Volume mounts: `/var/run/docker.sock:/var/run/docker.sock` (read-only is preferred but Portainer needs RW for many ops — use RW), `portainer-data:/data`.
   - Ports: `9443:9443` (HTTPS, self-signed), `9000:9000` (HTTP).
   - Networks: `monitoring-net` (so Prometheus *could* scrape later if Portainer exposes metrics; not required for now).
2. `stacks/deploy-portainer.sh`.
3. `pgadmin/servers.json` — pre-registered server entries:
   ```json
   {
     "Servers": {
       "1": {
         "Name": "Auth DB",
         "Group": "TrackIT",
         "Host": "auth-db",
         "Port": 5432,
         "MaintenanceDB": "auth_db",
         "Username": "auth_user",
         "SSLMode": "prefer"
       },
       "2": {
         "Name": "Data DB",
         "Group": "TrackIT",
         "Host": "data-db",
         "Port": 5432,
         "MaintenanceDB": "data_db",
         "Username": "data_user",
         "SSLMode": "prefer"
       }
     }
   }
   ```
4. `stacks/stack-pgadmin.yml`:
   - Image: `dpage/pgadmin4:latest`.
   - Placement: `node.role == manager`.
   - Volume mount: `./pgadmin/servers.json:/pgadmin4/servers.json:ro`, `pgadmin-data:/var/lib/pgadmin`.
   - Networks: `db-net` (must reach both DBs), `monitoring-net` (Portainer access).
   - Env: `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD`, `PGADMIN_CONFIG_SERVER_MODE=False` (single-user mode for the demo).
   - Ports: `5050:80`.
5. `stacks/deploy-pgadmin.sh`.

**Acceptance:**
- Portainer at `http://<manager-ip>:9000` shows the Swarm dashboard with all 3 nodes and all stacks.
- pgAdmin at `http://<manager-ip>:5050` — log in with the env credentials → both DBs pre-listed → can query `auth.users` and `data.workouts` (passwords still need to be entered manually per security model).

---

## Phase 9 — Architecture documentation

**Goal:** Anyone reading the repo understands the system in 5 minutes.

1. `docs/architecture.md`:
   - Embed the architecture diagram from the project document (`docs/images/architecture-diagram.png` — copy from the original PDF or recreate).
   - Sections: Overview, Networks (with the table from this plan), Cluster placement (with the table), Request flow examples (one for `/api/v1/auth/login`, one for `/api/v1/workouts`), Security boundaries (why Data Service has no auth, why DBs are on `db-net` only).
2. `docs/runbook.md`:
   - **Deploying from scratch:** `multipass/launch-cluster.sh` → `swarm/swarm-init.sh` → `swarm/join-workers.sh` → `swarm/label-nodes.sh` → `swarm/create-networks.sh` → `stacks/deploy-trackit.sh` → `stacks/deploy-monitoring.sh` → `stacks/deploy-portainer.sh` → `stacks/deploy-pgadmin.sh`.
   - **Updating a service image:** `docker service update --image florinionita/trackit-auth-service:<sha> trackit_auth-service`.
   - **Inspecting logs:** `docker service logs -f trackit_<svc>`.
   - **Scaling:** `docker service scale trackit_business-logic-service=3` (and what currently breaks because of in-memory goals — point to Business Logic Phase 9b).
   - **Common failures:** Postgres not ready when Auth boots (Spring Boot retries — wait), Kong 502 (service unhealthy — check `/actuator/health`), out-of-memory kill on a worker (bump VM RAM in `launch-cluster.sh`).
   - **Tearing down:** `docker stack rm trackit monitoring portainer pgadmin` → wait → `swarm/teardown.sh` → `multipass/destroy-cluster.sh`.
3. Update root `README.md` Quick Start: link to `docs/runbook.md` for the full path; show a 5-line "happy path" for someone with the cluster already running.

**Acceptance:** Following `docs/runbook.md` from a clean machine produces a working cluster end-to-end. (Test by deleting everything and re-doing it.)

---

## Phase 10 — CI/CD for the infrastructure repo

**Goal:** Catch broken stack files and bad Kong configs before they hit the cluster. **This is CI for *this* repo** — the per-service CI/CD pipelines live in each service's own repo (Auth's is already done).

1. `.github/workflows/lint-compose.yml`:
   - Trigger: `push`, `pull_request`.
   - Steps: checkout → run `docker compose -f compose/docker-compose.dev.yml config -q` (validates syntax). Then for each `stacks/*.yml`: `docker compose -f <file> config -q`. Fail on any error.
2. `.github/workflows/kong-validate.yml`:
   - Trigger: `push`, `pull_request`, paths: `kong/**`.
   - Steps: checkout → `docker run --rm -v ${{ github.workspace }}/kong:/kong kong:3 kong config -c /kong/kong.yml parse /kong/kong.yml`.
3. `.github/workflows/shellcheck.yml`:
   - Run `shellcheck` on every `*.sh` in the repo.
   - Use `ludeeus/action-shellcheck@master`.

**Acceptance:** Every PR runs three checks. Breaking `kong.yml` syntax → CI fails. Breaking a stack file → CI fails. Shell script with an unquoted variable → CI warns.

---

## Phase 11 — End-to-end smoke test

**Goal:** A scripted check that the whole system works after deploy. Useful for the project demo.

1. `scripts/smoke-test.sh`:
   - Inputs: `KONG_URL` (default `http://localhost:8000`).
   - Steps (each `set -e` / fail loud):
     1. `POST /api/v1/auth/register` (random username) → 201, capture access token.
     2. `POST /api/v1/auth/login` same creds → 200.
     3. `GET /api/v1/auth/validate` from inside the cluster (`docker exec` into business-logic) — verify it returns `valid:true`.
     4. `GET /api/v1/exercises` (Bearer) → 200, expect ≥10 items (the demo seed).
     5. `POST /api/v1/workouts` with one exercise → 201.
     6. `GET /api/v1/workouts` → 200, count = 1.
     7. `POST /api/v1/meals` → 201.
     8. `GET /api/v1/stats/nutrition/daily?date=$(date -u +%Y-%m-%d)` → 200, totals match.
     9. `GET /api/v1/dashboard` → 200, shape matches.
   - Print `✅ Smoke test passed` or `❌ Failed at step N`.
2. Document in `docs/runbook.md`.

**Acceptance:** Run end-to-end against a freshly deployed cluster — passes. Run against a deliberately broken cluster (stop `data-service`) — fails clearly at the workouts step.

---

## Phase 12 — Documentation polish & release

**Goal:** Repo is presentation-ready for the project deadline.

1. Final `README.md`:
   - Badges: GitHub Actions status, license.
   - One-paragraph project summary + link to umbrella project doc.
   - Architecture diagram inline.
   - **Three Quick Starts:**
     - "Just run the app" (single-host: `cd compose && docker compose up`).
     - "Full Swarm cluster" (link to runbook).
     - "Just inspect" (link to live demo URL if any, or screenshots).
   - Repo layout overview.
   - Link table: per-service repos + Docker Hub images.
   - Configuration reference: every env var, defaults, where it's used.
   - Known limitations + out-of-scope (copied from "Out of scope" below).
2. `CHANGELOG.md`: replace `## [Unreleased]` with `## [0.1.0] - YYYY-MM-DD`, add a fresh empty `## [Unreleased]`. Tag `v0.1.0`, push.
3. `docs/runbook.md`: final pass — make sure every command in it runs unmodified on a fresh machine.

---

## Versioning notes

- Pre-1.0: stack file shape may change between minors. Bump minor when adding a new stack or removing/renaming a service.
- After Etapa 1 ships and the stack is stable, cut `1.0.0`.

## Out of scope (intentionally)

- **TLS / HTTPS.** Kong serves HTTP only for the demo. Adding Let's Encrypt requires DNS, a public IP, and ACME — all overkill for a local Multipass cluster. If demoing on cloud later, add a phase using `acme` plugin or front Kong with Caddy.
- **Production secrets management.** Currently `.env` files. Migrate to Docker Swarm secrets (`docker secret create`) when going to a real environment. Documented in `docs/runbook.md` as future work.
- **Highly-available DBs.** Single-node Postgres for both `auth_db` and `data_db`. No replication, no failover. Acceptable for a course project.
- **Log aggregation (ELK / Loki).** Logs go to `docker service logs`. Adding Loki is a clear extension — drop it next to Prometheus on `monitoring-net`.
- **Alerting.** Prometheus scrapes but doesn't alert. Alertmanager is the natural next phase.
- **Per-service Grafana dashboards.** Per Mihai's responsibilities. This repo provides the empty `grafana/dashboards/` directory wired into provisioning; he drops `.json` files in.
- **CDN / load balancer in front of Kong.** Kong is the entry point. Adding HAProxy or cloud LB is a real-deployment concern, not a demo concern.
- **Backups.** No volume backup automation. For the demo, `docker exec auth-db pg_dump` on demand is enough.

If any of these become required, add them as new phases here, bump the minor version, and document in `CHANGELOG.md`.

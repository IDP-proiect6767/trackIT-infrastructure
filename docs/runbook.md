# TrackIT Infrastructure Runbook

Operational reference for the TrackIT Docker Swarm cluster. Follow the steps in order for a clean deploy from scratch.

---

## Deploying from Scratch

```bash
# 1. Provision three Multipass VMs with Docker pre-installed
bash multipass/launch-cluster.sh

# 2. Initialize Docker Swarm on the manager
bash swarm/swarm-init.sh

# 3. Join the two workers to the Swarm
bash swarm/join-workers.sh

# 4. Apply node placement labels
bash swarm/label-nodes.sh

# 5. Create the four overlay networks
bash swarm/create-networks.sh

# 6. Fill in secrets
cp stacks/.env.example stacks/.env
# Edit stacks/.env — set real passwords and JWT secret

# 7. Deploy the application stack
bash stacks/deploy-trackit.sh

# 8. Deploy the monitoring stack
bash stacks/deploy-monitoring.sh

# 9. Deploy Portainer
bash stacks/deploy-portainer.sh

# 10. Deploy pgAdmin
bash stacks/deploy-pgadmin.sh
```

After these steps:

| Service    | URL                              |
|------------|----------------------------------|
| Kong proxy | `http://<manager-ip>:8000`       |
| pgAdmin    | `http://<manager-ip>:5050`       |
| Prometheus | `http://<manager-ip>:9090`       |
| Grafana    | `http://<manager-ip>:3000`       |
| Portainer  | `http://<manager-ip>:9000`       |

Get manager IP: `multipass info trackit-manager | grep IPv4`

---

## Updating a Service Image

```bash
# Rolling update to a specific image SHA
docker service update \
  --image florinionita/trackit-auth-service:<sha> \
  trackit_auth-service

# Check rollout status
docker service ps trackit_auth-service
```

Same pattern for `trackit_business-logic-service` and `trackit_data-service`.

---

## Inspecting Logs

```bash
# Follow logs for a service
docker service logs -f trackit_auth-service
docker service logs -f trackit_business-logic-service
docker service logs -f trackit_data-service
docker service logs -f trackit_kong

# Show last 100 lines
docker service logs --tail 100 trackit_auth-service
```

---

## Scaling a Service

```bash
# Scale business logic to 3 replicas
docker service scale trackit_business-logic-service=3
```

> **Warning:** Business Logic Service currently stores user goals in-memory (not in the database). Scaling beyond 1 replica will cause goals to be silently lost on requests that hit different replicas. This is a known limitation — tracked in Business Logic Service Phase 9b. Fix the in-memory state before scaling.

---

## Running the Smoke Test

```bash
# Against the local Swarm
KONG_URL=http://<manager-ip>:8000 bash scripts/smoke-test.sh

# Against local dev compose
bash scripts/smoke-test.sh   # defaults to http://localhost:8000
```

---

## Common Failures

### Postgres not ready when Auth Service starts

Spring Boot retries the DB connection on startup. Wait up to 60 seconds. If Auth Service keeps crashing, check the DB password in `stacks/.env` and confirm `trackit_auth-db` is healthy:

```bash
docker service ps trackit_auth-db
```

### Kong 502 Bad Gateway

The upstream service is unhealthy or not reachable. Check:

```bash
docker service logs trackit_kong
docker service ps trackit_auth-service
# Confirm the service is on frontend-net
docker network inspect frontend-net
```

### Out-of-memory kill on a worker

Increase VM RAM in `multipass/launch-cluster.sh` (`MEMORY` variable, e.g. `4G`) and reprovision. Alternatively reduce concurrent services on that worker.

### Stack update conflicts (config already exists)

Docker Swarm configs are immutable by name. When you update `kong.yml` and redeploy, you may see:

```
config 'kong-config' already exists
```

Workaround — remove and redeploy:

```bash
docker stack rm trackit
# wait 10s for containers to stop
bash stacks/deploy-trackit.sh
```

---

## Tearing Down

```bash
# Remove all stacks
docker stack rm trackit monitoring portainer pgadmin

# Wait for containers to stop (~10s)
sleep 15

# Leave Swarm
bash swarm/teardown.sh

# Delete VMs
bash multipass/destroy-cluster.sh
```

---

## Secrets — Upgrade Path to Docker Swarm Secrets

Current setup uses `.env` files (acceptable for the demo). For production:

```bash
# Create secrets
echo "s3cr3t" | docker secret create auth_db_password -
echo "jwt-key-here" | docker secret create auth_jwt_secret -

# Reference in stack file:
# secrets:
#   auth_db_password:
#     external: true
# services:
#   auth-service:
#     secrets:
#       - auth_db_password
#     environment:
#       AUTH_DB_PASSWORD_FILE: /run/secrets/auth_db_password
```

The Spring Boot services would need to read from the file path instead of the env var directly (use `spring.config.import=optional:file:/run/secrets/` or a wrapper script).

---

## Adding a Grafana Dashboard

1. In Grafana, build the dashboard and export it as JSON (Dashboard → Share → Export → Save to file).
2. Drop the `.json` file into `grafana/dashboards/`.
3. Commit and push.
4. Grafana auto-loads dashboards from the provisioned path — no restart needed if running in dev compose. For Swarm, update the config:

```bash
docker service update --force monitoring_grafana
```

---

## Alerting (Future Work)

Prometheus is configured to scrape all services. To add alerting:

1. Add `rule_files` to `prometheus/prometheus.yml` pointing to `prometheus/alerts/*.yml`.
2. Write alert rules in YAML files under `prometheus/alerts/`.
3. Deploy Alertmanager alongside Prometheus on `monitoring-net`.
4. Configure `alerting:` block in `prometheus/prometheus.yml` to point to Alertmanager.

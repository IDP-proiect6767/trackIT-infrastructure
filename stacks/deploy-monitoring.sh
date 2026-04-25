#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found."
    echo "       Copy stacks/.env.example to stacks/.env and fill in secrets."
    exit 1
fi

# shellcheck source=/dev/null
set -a; source "$ENV_FILE"; set +a

echo "==> Deploying monitoring stack (Prometheus + Grafana)..."
docker stack deploy \
    --compose-file "$SCRIPT_DIR/stack-monitoring.yml" \
    monitoring

echo "==> Waiting for services..."
SERVICES=("monitoring_prometheus" "monitoring_grafana")
MAX_WAIT=60
WAITED=0

while true; do
    ALL_READY=true
    for svc in "${SERVICES[@]}"; do
        replicas=$(docker service ls --filter "name=$svc" --format "{{.Replicas}}" 2>/dev/null || echo "0/0")
        if [[ "$replicas" != "1/1" ]]; then
            ALL_READY=false
            break
        fi
    done
    $ALL_READY && break
    [[ $WAITED -ge $MAX_WAIT ]] && { echo "WARNING: Timeout. Check: docker service ls"; break; }
    sleep 5; WAITED=$((WAITED + 5))
    echo "    Still waiting... ($WAITED/${MAX_WAIT}s)"
done

echo ""
echo "==> Service status:"
docker service ls --filter "name=monitoring_"
echo ""
echo "Prometheus: http://<manager-ip>:9090"
echo "Grafana:    http://<manager-ip>:3000  (admin / \$GRAFANA_ADMIN_PASSWORD)"

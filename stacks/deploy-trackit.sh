#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found."
    echo "       Copy stacks/.env.example to stacks/.env and fill in secrets."
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

echo "==> Deploying TrackIT app stack..."
docker stack deploy \
    --compose-file "$SCRIPT_DIR/stack-trackit.yml" \
    --with-registry-auth \
    trackit

echo "==> Waiting for all services to be ready (1/1 replicas)..."
SERVICES=("trackit_auth-db" "trackit_data-db" "trackit_auth-service" "trackit_business-logic-service" "trackit_data-service" "trackit_kong")
MAX_WAIT=120
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
    if $ALL_READY; then
        break
    fi
    if [[ $WAITED -ge $MAX_WAIT ]]; then
        echo "WARNING: Timeout waiting for services. Check: docker service ls"
        break
    fi
    sleep 5
    WAITED=$((WAITED + 5))
    echo "    Still waiting... ($WAITED/${MAX_WAIT}s)"
done

echo ""
echo "==> Service status:"
docker service ls --filter "name=trackit_"
echo ""
echo "TrackIT stack deployed. Kong proxy: http://<manager-ip>:8000"

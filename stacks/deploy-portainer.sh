#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Deploying Portainer stack..."
docker stack deploy \
    --compose-file "$SCRIPT_DIR/stack-portainer.yml" \
    portainer

echo "==> Waiting for Portainer..."
MAX_WAIT=60; WAITED=0
while true; do
    replicas=$(docker service ls --filter "name=portainer_portainer" --format "{{.Replicas}}" 2>/dev/null || echo "0/0")
    [[ "$replicas" == "1/1" ]] && break
    [[ $WAITED -ge $MAX_WAIT ]] && { echo "WARNING: Timeout. Check: docker service ls"; break; }
    sleep 5; WAITED=$((WAITED + 5))
    echo "    Still waiting... ($WAITED/${MAX_WAIT}s)"
done

echo ""
echo "Portainer: http://<manager-ip>:9000"
echo "           https://<manager-ip>:9443  (self-signed TLS)"

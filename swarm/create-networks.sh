#!/usr/bin/env bash
set -euo pipefail

MANAGER_NAME="trackit-manager"

NETWORKS=(
    "frontend-net"
    "backend-net"
    "db-net"
    "monitoring-net"
)

echo "==> Creating overlay networks on $MANAGER_NAME..."

for net in "${NETWORKS[@]}"; do
    if multipass exec "$MANAGER_NAME" -- docker network inspect "$net" > /dev/null 2>&1; then
        echo "    $net already exists, skipping."
    else
        echo "    Creating $net..."
        multipass exec "$MANAGER_NAME" -- \
            docker network create --driver overlay --attachable "$net"
    fi
done

echo ""
echo "==> Network list:"
multipass exec "$MANAGER_NAME" -- docker network ls --filter driver=overlay
echo ""
echo "Networks ready. Next step: deploy stacks."

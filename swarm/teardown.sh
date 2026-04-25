#!/usr/bin/env bash
set -euo pipefail

MANAGER_NAME="trackit-manager"
WORKER1_NAME="trackit-worker-1"
WORKER2_NAME="trackit-worker-2"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.swarm-state"

echo "==> Tearing down Docker Swarm..."

for worker in "$WORKER1_NAME" "$WORKER2_NAME"; do
    echo "    $worker leaving swarm..."
    multipass exec "$worker" -- docker swarm leave || true
done

echo "    Manager leaving swarm (force)..."
multipass exec "$MANAGER_NAME" -- docker swarm leave --force || true

if [[ -f "$STATE_FILE" ]]; then
    rm "$STATE_FILE"
    echo "    Removed $STATE_FILE"
fi

echo "Done. VMs still exist — run multipass/destroy-cluster.sh to delete them."

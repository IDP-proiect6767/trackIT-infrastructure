#!/usr/bin/env bash
set -euo pipefail

MANAGER_NAME="trackit-manager"
WORKER1_NAME="trackit-worker-1"
WORKER2_NAME="trackit-worker-2"

echo "==> Applying node labels..."

multipass exec "$MANAGER_NAME" -- \
    docker node update --label-add role=auth "$WORKER1_NAME"

multipass exec "$MANAGER_NAME" -- \
    docker node update --label-add role=app "$WORKER2_NAME"

echo "==> Verifying labels:"
for node in "$WORKER1_NAME" "$WORKER2_NAME"; do
    echo "    $node labels:"
    multipass exec "$MANAGER_NAME" -- \
        docker node inspect "$node" --format '    {{ .Spec.Labels }}'
done

echo ""
echo "Next step: bash swarm/create-networks.sh"

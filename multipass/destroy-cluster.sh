#!/usr/bin/env bash
set -euo pipefail

MANAGER_NAME="trackit-manager"
WORKER1_NAME="trackit-worker-1"
WORKER2_NAME="trackit-worker-2"

echo "==> Stopping and deleting TrackIT cluster VMs..."
for name in "$MANAGER_NAME" "$WORKER1_NAME" "$WORKER2_NAME"; do
    if multipass info "$name" > /dev/null 2>&1; then
        echo "    Deleting $name..."
        multipass delete --purge "$name"
    else
        echo "    $name not found, skipping."
    fi
done
echo "Done. All VMs deleted."

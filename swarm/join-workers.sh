#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.swarm-state"

WORKER1_NAME="trackit-worker-1"
WORKER2_NAME="trackit-worker-2"
MANAGER_NAME="trackit-manager"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "ERROR: $STATE_FILE not found. Run swarm-init.sh first."
    exit 1
fi

# shellcheck source=/dev/null
source "$STATE_FILE"

echo "==> Joining workers to Swarm (manager: $MANAGER_IP)..."

for worker in "$WORKER1_NAME" "$WORKER2_NAME"; do
    echo "    Joining $worker..."
    multipass exec "$worker" -- docker swarm join --token "$JOIN_TOKEN" "${MANAGER_IP}:2377"
done

echo ""
echo "==> Verifying cluster:"
multipass exec "$MANAGER_NAME" -- docker node ls
echo ""
echo "Next step: bash swarm/label-nodes.sh"

#!/usr/bin/env bash
set -euo pipefail

MANAGER_NAME="trackit-manager"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.swarm-state"

echo "==> Initializing Docker Swarm on $MANAGER_NAME..."

MANAGER_IP=$(multipass info "$MANAGER_NAME" --format json \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['info']['$MANAGER_NAME']['ipv4'][0])")

echo "    Manager IP: $MANAGER_IP"

multipass exec "$MANAGER_NAME" -- docker swarm init --advertise-addr "$MANAGER_IP"

JOIN_TOKEN=$(multipass exec "$MANAGER_NAME" -- docker swarm join-token -q worker)

echo "MANAGER_IP=$MANAGER_IP" > "$STATE_FILE"
echo "JOIN_TOKEN=$JOIN_TOKEN" >> "$STATE_FILE"

echo "    Swarm state saved to $STATE_FILE"
echo "    Manager IP:   $MANAGER_IP"
echo "    Worker token: $JOIN_TOKEN"
echo ""
echo "Next step: bash swarm/join-workers.sh"

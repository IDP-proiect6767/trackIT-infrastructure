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

echo "==> Deploying pgAdmin stack..."
docker stack deploy \
    --compose-file "$SCRIPT_DIR/stack-pgadmin.yml" \
    pgadmin

echo "==> Waiting for pgAdmin..."
MAX_WAIT=60; WAITED=0
while true; do
    replicas=$(docker service ls --filter "name=pgadmin_pgadmin" --format "{{.Replicas}}" 2>/dev/null || echo "0/0")
    [[ "$replicas" == "1/1" ]] && break
    [[ $WAITED -ge $MAX_WAIT ]] && { echo "WARNING: Timeout. Check: docker service ls"; break; }
    sleep 5; WAITED=$((WAITED + 5))
    echo "    Still waiting... ($WAITED/${MAX_WAIT}s)"
done

echo ""
echo "pgAdmin: http://<manager-ip>:5050"
echo "         Login: \$PGADMIN_DEFAULT_EMAIL / \$PGADMIN_DEFAULT_PASSWORD"

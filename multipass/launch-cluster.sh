#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MANAGER_NAME="trackit-manager"
WORKER1_NAME="trackit-worker-1"
WORKER2_NAME="trackit-worker-2"

CPUS=2
MEMORY="2G"
DISK="10G"
IMAGE="22.04"

launch_vm() {
    local name="$1"
    echo "==> Launching VM: $name"
    multipass launch \
        --name "$name" \
        --cpus "$CPUS" \
        --memory "$MEMORY" \
        --disk "$DISK" \
        --cloud-init "$SCRIPT_DIR/cloud-init.yaml" \
        "$IMAGE"
    echo "    Waiting for Docker on $name..."
    # Retry up to 30s for Docker to be available
    for _ in $(seq 1 30); do
        if multipass exec "$name" -- docker --version > /dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    echo "    Docker version on $name: $(multipass exec "$name" -- docker --version)"
}

launch_vm "$MANAGER_NAME"
launch_vm "$WORKER1_NAME"
launch_vm "$WORKER2_NAME"

# Print summary table
echo ""
echo "=== Cluster Summary ==="
printf "%-22s %-18s %-10s\n" "VM Name" "IP Address" "Role"
printf "%-22s %-18s %-10s\n" "-------" "----------" "----"
for name in "$MANAGER_NAME" "$WORKER1_NAME" "$WORKER2_NAME"; do
    ip=$(multipass info "$name" --format json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['info']['$name']['ipv4'][0])" 2>/dev/null || echo "unknown")
    case "$name" in
        "$MANAGER_NAME") role="manager" ;;
        "$WORKER1_NAME") role="worker-1 (auth)" ;;
        *)               role="worker-2 (app)" ;;
    esac
    printf "%-22s %-18s %-10s\n" "$name" "$ip" "$role"
done
echo ""
echo "All VMs are up. Next step: bash swarm/swarm-init.sh"

#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ssh-into.sh [manager|worker-1|worker-2]
TARGET="${1:-manager}"

case "$TARGET" in
    manager)  VM="trackit-manager" ;;
    worker-1) VM="trackit-worker-1" ;;
    worker-2) VM="trackit-worker-2" ;;
    *)
        echo "Usage: $0 [manager|worker-1|worker-2]"
        exit 1
        ;;
esac

echo "==> Connecting to $VM..."
multipass shell "$VM"

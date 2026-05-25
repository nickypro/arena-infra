#!/usr/bin/env bash
# Poll until all expected pods are reachable, then run update.sh to refresh the nginx proxy.
# Useful after `create_new_pods.py` — pods take 30s to several minutes to allocate IPs.
#
# Defaults: poll every 2 min for up to 10 min, expected count = len(MACHINE_NAME_LIST).
# Override via env vars: TIMEOUT=900 INTERVAL=60 EXPECTED=20 ./wait_and_update.sh

set -euo pipefail

TIMEOUT="${TIMEOUT:-600}"
INTERVAL="${INTERVAL:-120}"
EXPECTED="${EXPECTED:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.env"
EXPECTED="${EXPECTED:-${#MACHINE_NAME_LIST[@]}}"

echo "Waiting for $EXPECTED pods (timeout ${TIMEOUT}s, interval ${INTERVAL}s)..."

start=$(date +%s)
while true; do
  elapsed=$(($(date +%s) - start))
  ready=$(python3 "$SCRIPT_DIR/nginx_pods.py" 2>/dev/null | grep -cE '^upstream ' || true)
  echo "[$(date +%H:%M:%S)] ready=$ready/$EXPECTED, elapsed=${elapsed}s"

  if [ "$ready" -ge "$EXPECTED" ]; then
    echo "All $EXPECTED pods ready. Updating nginx..."
    bash "$SCRIPT_DIR/update.sh"
    exit 0
  fi

  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    echo "Timeout after ${TIMEOUT}s with $ready/$EXPECTED ready. Updating with current set..."
    bash "$SCRIPT_DIR/update.sh"
    exit 1
  fi

  sleep "$INTERVAL"
done

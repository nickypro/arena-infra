#!/usr/bin/env bash
# send_cmd.sh — run a command on all hosts in MACHINE_NAME_LIST

# Load MACHINE_NAME_LIST (array) and MACHINE_NAME_PREFIX from ../config.env
source "$(dirname "$0")/../config.env"

SSH_USER="${SSH_USER:-root}"
PREFIX="${MACHINE_NAME_PREFIX:-arena6}"

if [ $# -lt 1 ]; then
  echo "Usage: $(basename "$0") <command...>"
  echo "Example: $(basename "$0") \"apt update\""
  exit 1
fi

# Safely reconstruct the command from all args
printf -v CMD_STR '%q ' "$@"
CMD_STR=${CMD_STR% }

for name in "${MACHINE_NAME_LIST[@]}"; do
  host="${PREFIX}-${name}"
  echo "[$host] running: $*"
  ssh "${SSH_USER}@${host}" bash -lc "$CMD_STR"
done
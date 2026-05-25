#!/usr/bin/env bash
# set_names.sh — write the short machine name to ~/.name on each host

# Load MACHINE_NAME_LIST (array) and MACHINE_NAME_PREFIX from ../config.env
source "$(dirname "$0")/../config.env"

SSH_USER="${SSH_USER:-root}"                # default to root
PREFIX="${MACHINE_NAME_PREFIX:-arena6}"     # default prefix if not set

for name in "${MACHINE_NAME_LIST[@]}"; do
  host="${PREFIX}-${name}"
  echo "Setting ~/.name on ${host} to '${name}'"
  ssh "${SSH_USER}@${host}" "printf '%s\n' 'MACHINE_NAME=${name}' > ~/.name"
done

#!/usr/bin/env bash
# List current git branches for all machines in a table format

source "$(dirname "$0")/../config.env"

SSH_KEY="$SHARED_SSH_KEY_PATH"
SSH_USER="root"
MAX_PARALLEL=10
REMOTE_GIT_DIR="ARENA_3.0"

SSH_OPTS=(-q -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i "$SSH_KEY")

TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

get_branch() {
    local name="$1"
    local host="$MACHINE_NAME_PREFIX-$name"
    local outfile="$TMP_DIR/$name"
    
    branch=$(ssh "${SSH_OPTS[@]}" "$SSH_USER@$host" "cd \$HOME/$REMOTE_GIT_DIR && git rev-parse --abbrev-ref HEAD" 2>/dev/null)
    
    if [ -n "$branch" ]; then
        echo "$branch" > "$outfile"
    else
        echo "ERROR" > "$outfile"
    fi
}

echo "Fetching branches from ${#MACHINE_NAME_LIST[@]} machines..."

# Launch parallel queries
pids=()
for name in "${MACHINE_NAME_LIST[@]}"; do
    while [ ${#pids[@]} -ge $MAX_PARALLEL ]; do
        wait -n 2>/dev/null || break
        new_pids=()
        for p in "${pids[@]}"; do
            kill -0 "$p" 2>/dev/null && new_pids+=("$p")
        done
        pids=("${new_pids[@]}")
    done
    
    get_branch "$name" &
    pids+=($!)
done

wait
echo

# Print table
printf "%-15s | %s\n" "MACHINE" "BRANCH"
printf "%-15s-+-%s\n" "---------------" "$(printf '%0.s-' {1..60})"

for name in "${MACHINE_NAME_LIST[@]}"; do
    branch=$(cat "$TMP_DIR/$name" 2>/dev/null || echo "UNREACHABLE")
    printf "%-15s | %s\n" "$name" "$branch"
done




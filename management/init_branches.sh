#!/usr/bin/env bash
# Parse command line arguments
EXCLUDE_LIST=()
DAY_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --exclude)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                echo "ERROR: --exclude requires at least one host name"
                exit 1
            fi
            shift
            while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do
                EXCLUDE_LIST+=("$1")
                shift
            done
            ;;
        *)
            if [ -z "$DAY_NAME" ]; then
                DAY_NAME="$1"
            else
                echo "ERROR: Unexpected argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$DAY_NAME" ]; then
    echo "ERROR: DAY_NAME (e.g. 'w0d1') argument required"
    echo "Example: $0 w0d1"
    echo "         $0 w0d1 --exclude apple bloom"
    exit 1
fi

# --- Configuration ---
source "$(dirname "$0")/../config.env"

SSH_KEY="$SHARED_SSH_KEY_PATH"
SSH_USER="root"
MAX_PARALLEL=10
REMOTE_GIT_DIR="ARENA_3.0"

SSH_OPTS=(-o ConnectTimeout=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i "$SSH_KEY")
SSH_TEST_OPTS=(-q -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i "$SSH_KEY")

TMP_LOG_DIR="$(dirname "$0")/../logs/tmp_git_init_logs"
mkdir -p "$TMP_LOG_DIR"

# Process a single host
process_host() {
    local nato_name="$1"
    local host="$MACHINE_NAME_PREFIX-$nato_name"
    local logfile="$TMP_LOG_DIR/log_$nato_name.log"
    local DEFAULT_BRANCH="autocommit-$MACHINE_NAME_PREFIX-$DAY_NAME-$nato_name"

    {
        echo "=== Processing $host (Default: $DEFAULT_BRANCH) ==="

        # Connection test
        if ! ssh "${SSH_TEST_OPTS[@]}" "$SSH_USER@$host" exit; then
            echo "[FAIL] Connection failed or timed out."
            exit 1
        fi

        # Run git commands remotely (using unquoted heredoc for local variable expansion)
        ssh "${SSH_OPTS[@]}" "$SSH_USER@$host" bash <<REMOTE_SCRIPT
cd "\$HOME/$REMOTE_GIT_DIR" || exit 1

echo "--- Fetching from origin ---"
git fetch --all --prune || exit 1

echo "--- Creating branch: $DEFAULT_BRANCH ---"
git checkout -b "$DEFAULT_BRANCH" 2>/dev/null || git checkout "$DEFAULT_BRANCH" || exit 1

CURRENT=\$(git rev-parse --abbrev-ref HEAD)
echo "--- Pushing \$CURRENT to origin ---"
git push -u origin "\$CURRENT" 2>&1 | grep -v "Everything up-to-date" || true

echo "[ OK ] Branch initialization completed successfully"
REMOTE_SCRIPT

        local status=$?
        if [ $status -ne 0 ]; then
            echo "[FAIL] Branch initialization failed (exit $status)"
        fi
    } > "$logfile" 2>&1
}

# --- Main ---
# Filter excluded hosts
FILTERED_HOST_LIST=()
for name in "${MACHINE_NAME_LIST[@]}"; do
    excluded=false
    for ex in "${EXCLUDE_LIST[@]}"; do
        [[ "$name" == "$ex" ]] && excluded=true && break
    done
    $excluded || FILTERED_HOST_LIST+=("$name")
done

if [ ${#EXCLUDE_LIST[@]} -gt 0 ]; then
    echo "Excluding: ${EXCLUDE_LIST[*]}"
fi
echo "Processing ${#FILTERED_HOST_LIST[@]} hosts (max parallel: $MAX_PARALLEL)..."

# Launch parallel processes
pids=()
for name in "${FILTERED_HOST_LIST[@]}"; do
    # Limit parallelism
    while [ ${#pids[@]} -ge $MAX_PARALLEL ]; do
        wait -n 2>/dev/null || break
        # Clean up finished pids
        new_pids=()
        for p in "${pids[@]}"; do
            kill -0 "$p" 2>/dev/null && new_pids+=("$p")
        done
        pids=("${new_pids[@]}")
    done

    process_host "$name" &
    pids+=($!)
done

echo "Waiting for ${#pids[@]} remaining processes..."
wait

# --- Results ---
echo
successful=() conn_failed=() init_failed=()

for name in "${FILTERED_HOST_LIST[@]}"; do
    host="${MACHINE_NAME_PREFIX}-$name"
    log="$TMP_LOG_DIR/log_$name.log"

    [ -f "$log" ] && cat "$log" && echo

    if grep -q "\[ OK \]" "$log" 2>/dev/null; then
        successful+=("$host")
    elif grep -q "Connection failed" "$log" 2>/dev/null; then
        conn_failed+=("$host")
    else
        init_failed+=("$host")
    fi
done

echo "--- Summary ---"
echo "Processed: ${#FILTERED_HOST_LIST[@]}"
[ ${#EXCLUDE_LIST[@]} -gt 0 ] && echo "Excluded: ${EXCLUDE_LIST[*]}"
echo
echo "[ OK ] Successful (${#successful[@]}):"
[ ${#successful[@]} -gt 0 ] && printf "  %s\n" "${successful[@]}" || echo "  None"
echo
echo "[FAIL] Connection Failed (${#conn_failed[@]}):"
[ ${#conn_failed[@]} -gt 0 ] && printf "  %s\n" "${conn_failed[@]}" || echo "  None"
echo
echo "[FAIL] Init Failed (${#init_failed[@]}):"
[ ${#init_failed[@]} -gt 0 ] && printf "  %s\n" "${init_failed[@]}" || echo "  None"
echo "---------------"
echo "Logs: $TMP_LOG_DIR"

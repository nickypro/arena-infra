#!/usr/bin/env bash
# Commit and push changes on all machines (to their CURRENT branch)
# Will NOT push to main/master branches for safety

EXCLUDE_LIST=()
COMMIT_MSG="auto sync $(date +%Y-%m-%d_%H:%M)"

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
        -m|--message)
            if [ -z "$2" ]; then
                echo "ERROR: -m/--message requires a commit message"
                exit 1
            fi
            COMMIT_MSG="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--exclude host1 host2 ...] [-m 'commit message']"
            echo "Example: $0"
            echo "         $0 --exclude apple bloom"
            echo "         $0 -m 'end of day backup'"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            echo "Use --help for usage"
            exit 1
            ;;
    esac
done

# --- Configuration ---
source "$(dirname "$0")/../config.env"

SSH_KEY="$SHARED_SSH_KEY_PATH"
SSH_USER="root"
MAX_PARALLEL=10
REMOTE_GIT_DIR="ARENA_3.0"

SSH_OPTS=(-o ConnectTimeout=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i "$SSH_KEY")
SSH_TEST_OPTS=(-q -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i "$SSH_KEY")

TMP_LOG_DIR="$(dirname "$0")/../logs/tmp_git_sync_logs"
mkdir -p "$TMP_LOG_DIR"

process_host() {
    local nato_name="$1"
    local host="$MACHINE_NAME_PREFIX-$nato_name"
    local logfile="$TMP_LOG_DIR/log_$nato_name.log"

    {
        echo "=== $host ==="

        # Connection test
        if ! ssh "${SSH_TEST_OPTS[@]}" "$SSH_USER@$host" exit; then
            echo "[FAIL] Connection failed"
            exit 1
        fi

        # Run git commands remotely (using unquoted heredoc for local variable expansion)
        ssh "${SSH_OPTS[@]}" "$SSH_USER@$host" bash <<REMOTE_SCRIPT
cd "\$HOME/$REMOTE_GIT_DIR" || exit 1

BRANCH=\$(git rev-parse --abbrev-ref HEAD)
echo "Branch: \$BRANCH"

# Safety check - don't push to main/master
if [[ "\$BRANCH" == "main" || "\$BRANCH" == "master" ]]; then
    echo "[SKIP] Won't push to \$BRANCH - use init_branches.sh first"
    exit 2
fi

# Configure git identity if needed
git config user.name 2>/dev/null || git config user.name "Arena Autocommit"
git config user.email 2>/dev/null || git config user.email "autocommit@arena.education"

# Stage all changes
git add .

# Check if there's anything to commit
if git diff --cached --quiet; then
    echo "[OK] Nothing to commit"
else
    git commit -m "$COMMIT_MSG" || exit 1
    echo "[OK] Committed"
fi

# Push (set upstream if needed)
git push -u origin "\$BRANCH" || exit 1
echo "[OK] Pushed to \$BRANCH"
REMOTE_SCRIPT

        local status=$?
        case $status in
            0) echo "[ OK ] Synced successfully" ;;
            2) echo "[SKIP] Skipped (protected branch)" ;;
            *) echo "[FAIL] Git operation failed (exit $status)" ;;
        esac
    } > "$logfile" 2>&1
}

# --- Main ---
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
echo "Syncing ${#FILTERED_HOST_LIST[@]} hosts (max parallel: $MAX_PARALLEL)..."
echo "Commit message: $COMMIT_MSG"
echo

# Launch parallel processes
pids=()
for name in "${FILTERED_HOST_LIST[@]}"; do
    while [ ${#pids[@]} -ge $MAX_PARALLEL ]; do
        wait -n 2>/dev/null || break
        new_pids=()
        for p in "${pids[@]}"; do
            kill -0 "$p" 2>/dev/null && new_pids+=("$p")
        done
        pids=("${new_pids[@]}")
    done

    process_host "$name" &
    pids+=($!)
done

wait

# --- Results ---
echo
successful=() skipped=() conn_failed=() git_failed=()

for name in "${FILTERED_HOST_LIST[@]}"; do
    host="${MACHINE_NAME_PREFIX}-$name"
    log="$TMP_LOG_DIR/log_$name.log"
    
    [ -f "$log" ] && cat "$log" && echo
    
    if grep -q "\[ OK \] Synced" "$log" 2>/dev/null; then
        branch=$(grep "^Branch:" "$log" | cut -d' ' -f2)
        successful+=("$host → $branch")
    elif grep -q "\[SKIP\]" "$log" 2>/dev/null; then
        skipped+=("$host (on main/master)")
    elif grep -q "Connection failed" "$log" 2>/dev/null; then
        conn_failed+=("$host")
    else
        git_failed+=("$host")
    fi
done

echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo
echo "[ OK ] Synced (${#successful[@]}):"
if [ ${#successful[@]} -gt 0 ]; then printf "  %s\n" "${successful[@]}"; else echo "  None"; fi
echo
echo "[SKIP] Skipped - protected branch (${#skipped[@]}):"
if [ ${#skipped[@]} -gt 0 ]; then printf "  %s\n" "${skipped[@]}"; else echo "  None"; fi
echo
echo "[FAIL] Connection failed (${#conn_failed[@]}):"
if [ ${#conn_failed[@]} -gt 0 ]; then printf "  %s\n" "${conn_failed[@]}"; else echo "  None"; fi
echo
echo "[FAIL] Git failed (${#git_failed[@]}):"
if [ ${#git_failed[@]} -gt 0 ]; then printf "  %s\n" "${git_failed[@]}"; else echo "  None"; fi
echo
echo "Logs: $TMP_LOG_DIR"

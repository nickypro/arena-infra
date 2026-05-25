#!/usr/bin/env bash
# Get DAY_NAME from command line argument
if [ $# -eq 0 ]; then
    echo "ERROR: DAY_NAME (eg: "w0d1") argument required"
    echo "Example: $0 w0d1"
    exit 1
fi

DAY_NAME="$1"

# --- Configuration (from ../config.env) ---
source "$(dirname "$0")/../config.env"

SSH_KEY="$SHARED_SSH_KEY_PATH"

# User for SSH connection
SSH_USER="root"  # Change this if you use a different user

# Max number of parallel processes
MAX_PARALLEL=10

# Base directory for Git operations on remote host
REMOTE_GIT_DIR="ARENA_3.0" # Assumes this exists under $HOME

# SSH options
SSH_OPTS=(
  -o ConnectTimeout=30
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -i "$SSH_KEY"
)
SSH_CONNECT_TEST_OPTS=(
  -q -o BatchMode=yes -o ConnectTimeout=5
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR -i "$SSH_KEY"
)
# --- End Configuration ---

# Temporary directory for logs
TMP_LOG_DIR="./logs/tmp_git_pull_logs"
mkdir -p "$TMP_LOG_DIR"

# Function to process a single host
process_host() {
  local nato_name="$1"
  local host="$MACHINE_NAME_PREFIX-$nato_name"
  local logfile="$TMP_LOG_DIR/log_$nato_name.log"
  local BRANCH_NAME="autocommit-$MACHINE_NAME_PREFIX-$DAY_NAME-$nato_name"
  local remote_repo_path="\$HOME/$REMOTE_GIT_DIR"

  echo "=== Processing host $host (Branch: $BRANCH_NAME) ===" > "$logfile"

  # --- Connection Test ---
  echo "Testing connection to $host..." >> "$logfile"
  if ! ssh "${SSH_CONNECT_TEST_OPTS[@]}" "$SSH_USER@$host" exit; then
    echo "[FAIL] Connection failed or timed out." >> "$logfile"
    return 1
  fi
  echo "Connection successful." >> "$logfile"

  # --- Construct Git Commands (gentle: no stashing, skip if unsafe) ---
  local git_commands="cd \"$remote_repo_path\" && \
echo '--- [1/5] Checking Git Status Before Changes ---' && \
git status --short && \
echo '--- [2/5] Fetching from origin ---' && \
(git fetch --all --prune || { echo '[ERROR] Fetch failed'; exit 20; }) && \
echo '--- [3/5] Safety checks and branch selection ---' && \
if ! (git diff --quiet && git diff --cached --quiet); then \
  echo '[SKIP] Working tree has local changes; skipping checkout and pull to avoid overwriting.'; \
else \
  if git rev-parse --verify '$BRANCH_NAME' >/dev/null 2>&1; then \
    git checkout '$BRANCH_NAME' || { echo '[SKIP] Could not checkout $BRANCH_NAME safely; leaving repo unchanged.'; exit 0; }; \
  elif git ls-remote --exit-code --heads origin '$BRANCH_NAME' >/dev/null 2>&1; then \
    git checkout -t 'origin/$BRANCH_NAME' || { echo '[SKIP] Could not track-checkout $BRANCH_NAME safely; leaving repo unchanged.'; exit 0; }; \
  else \
    echo '[SKIP] Branch $BRANCH_NAME not found on origin; skipping.'; \
  fi; \
    if git rev-parse --abbrev-ref HEAD | grep -qx '$BRANCH_NAME'; then \
    if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then \
      if git ls-remote --exit-code --heads origin '$BRANCH_NAME' >/dev/null 2>&1; then \
        git branch --set-upstream-to=origin/'$BRANCH_NAME' '$BRANCH_NAME' && echo '[INFO] Set upstream to origin/$BRANCH_NAME' || echo '[SKIP] Could not set upstream'; \
      else \
        echo '[SKIP] No origin/$BRANCH_NAME to set as upstream'; \
      fi; \
    fi; \
    echo '--- [4/5] Pulling latest from origin (fast-forward only) ---'; \
    ( git pull --ff-only origin '$BRANCH_NAME' && echo '[INFO] Updated via fast-forward.' ) || echo '[SKIP] Pull not fast-forward or other issue; left unchanged.'; \
  fi; \
fi && \
echo '--- Git operations completed (pull may have been skipped) ---'"

  echo "Running Git commands on $host..." >> "$logfile"
  echo "Executing on remote:" >> "$logfile"
  echo "$git_commands" | sed "s/\\\$HOME/~/" >> "$logfile"
  echo "--- Remote Output ---" >> "$logfile"

  ssh "${SSH_OPTS[@]}" "$SSH_USER@$host" "$git_commands" >> "$logfile" 2>&1
  local ssh_status=$?

  if [ $ssh_status -eq 0 ]; then
    echo "[ OK ] Git commands completed successfully on $host." >> "$logfile"
    return 0
  else
    local reason=""
    case $ssh_status in
      20) reason="(Fetch Failed)" ;;
       *) reason="(Unknown Git Error - Exit Status: $ssh_status)" ;;
    esac
    echo "[FAIL] Git commands failed on $host $reason. Check log for details." >> "$logfile"
    return 3
  fi
}

# --- Main Execution Logic ---
pids=()

echo "Launching Git pull process for ${#MACHINE_NAME_LIST[@]} hosts (Max parallel: $MAX_PARALLEL)..."

for name in "${MACHINE_NAME_LIST[@]}"; do
  log_file="$TMP_LOG_DIR/log_$name.log"

  if [ ${#pids[@]} -ge $MAX_PARALLEL ]; then
    wait -n "${pids[@]}"
    new_pids=()
    for pid_chk in "${pids[@]}"; do
        if kill -0 "$pid_chk" 2>/dev/null; then new_pids+=("$pid_chk"); fi
    done
    pids=("${new_pids[@]}")
  fi

  process_host "$name" > "$log_file" 2>&1 &
  pids+=($!)
done

echo "Waiting for remaining processes (${#pids[@]}) to finish..."
wait

echo "All processes finished. Consolidating results..."
echo

# --- Consolidate and Print Results ---
successful_hosts=()
conn_failed_hosts=()
git_failed_hosts=()

for name in "${MACHINE_NAME_LIST[@]}"; do
  host="${MACHINE_NAME_PREFIX}-$name"
  log_file="$TMP_LOG_DIR/log_$name.log"
  if [ -f "$log_file" ]; then
    cat "$log_file"
    echo
    if grep -q "\[ OK \] Git commands completed successfully" "$log_file"; then
      successful_hosts+=("$host")
    elif grep -q "\[FAIL\] Connection failed" "$log_file"; then
      conn_failed_hosts+=("$host")
    elif grep -q "\[FAIL\] Git commands failed" "$log_file"; then
      reason=$(grep "\[FAIL\] Git commands failed" "$log_file" | sed -n 's/.*failed on .* \(\(.*\)\)\. Check log.*/\1/p')
      if [ -n "$reason" ]; then
         git_failed_hosts+=("$host $reason")
      else
         git_failed_hosts+=("$host (Git Failed)")
      fi
    else
       git_failed_hosts+=("$host (Unknown Error/State)")
    fi
  else
    conn_failed_hosts+=("$host (Log file missing)")
  fi
done

# --- Final Summary ---
echo "--- Summary ---"
echo "Total hosts processed: ${#MACHINE_NAME_LIST[@]}"
echo
echo "[ OK ] Successful Hosts (${#successful_hosts[@]}):"
if [ ${#successful_hosts[@]} -gt 0 ]; then printf "  %s\n" "${successful_hosts[@]}"; else echo "  None"; fi
echo
echo "[FAIL] Connection Failed Hosts (${#conn_failed_hosts[@]}):"
if [ ${#conn_failed_hosts[@]} -gt 0 ]; then printf "  %s\n" "${conn_failed_hosts[@]}"; else echo "  None"; fi
echo
echo "[FAIL] Git Command Failed Hosts (${#git_failed_hosts[@]}):"
if [ ${#git_failed_hosts[@]} -gt 0 ]; then printf "  %s\n" "${git_failed_hosts[@]}"; else echo "  None"; fi
echo "---------------"

# --- Cleanup ---
# rm -rf "$TMP_LOG_DIR"
echo "Individual logs are in $TMP_LOG_DIR"

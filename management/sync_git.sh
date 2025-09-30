#!/bin/bash
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
  -o ConnectTimeout=30      # Longer timeout for git operations
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
TMP_LOG_DIR="$(dirname "$0")/../logs/tmp_git_sync_logs"
mkdir -p "$TMP_LOG_DIR"

# Function to process a single host
process_host() {
  local nato_name="$1"
  local host="$MACHINE_NAME_PREFIX-$nato_name"
  local logfile="$TMP_LOG_DIR/log_$nato_name.log"
  # Define the branch name - depends on nato_name
  local BRANCH_NAME="autocommit-$MACHINE_NAME_PREFIX-$DAY_NAME-$nato_name"
  # Construct remote path using \$HOME for remote expansion
  local remote_repo_path="\$HOME/$REMOTE_GIT_DIR"

  echo "=== Processing host $host (Branch: $BRANCH_NAME) ===" > "$logfile"

  # --- Connection Test ---
  echo "Testing connection to $host..." >> "$logfile"
  if ! ssh "${SSH_CONNECT_TEST_OPTS[@]}" "$SSH_USER@$host" exit; then
    echo "[FAIL] Connection failed or timed out." >> "$logfile"
    return 1 # Connection Failure
  fi
  echo "Connection successful." >> "$logfile"

  # --- Construct Git Commands with Enhanced Logging & Error Checks ---
  # $BRANCH_NAME is expanded locally here.
  # Commands are chained with &&. || { ...; exit N; } handles errors.
  # Single quotes protect echo messages. Redirect git config checks.
  local git_commands="cd \"$remote_repo_path\" && \
echo '--- [1/6] Checking Git Status Before Changes ---' && \
git status --short && \
echo '--- [2/6] Configuring Git Identity (if needed) ---' && \
(git config --get user.name >/dev/null 2>&1 || git config user.name 'Arena Autocommit') && \
(git config --get user.email >/dev/null 2>&1 || git config user.email 'autocommit@arena.education') && \
echo '--- [3/6] Staging All Changes ---' && \
git add . && \
echo '--- [4/6] Committing Changes ---' && \
( git diff --cached --quiet && echo '[INFO] Nothing to commit; continuing' || git commit -m 'auto commit $DAY_NAME' ) || { echo '[ERROR] Commit failed'; exit 10; } && \
echo '--- [5/6] Creating/Checking Out Branch: $BRANCH_NAME ---' && \
(git checkout -b '$BRANCH_NAME' 2>/dev/null || git checkout '$BRANCH_NAME' || git checkout -t 'origin/$BRANCH_NAME') && \
echo '--- [6/6] Pushing Branch to Origin ---' && \
(git push --set-upstream origin '$BRANCH_NAME' || { echo '[ERROR] Push failed'; exit 12; }) && \
echo '--- Git operations completed successfully ---'"

  echo "Running Git commands on $host..." >> "$logfile"
  echo "Executing on remote:" >> "$logfile"
  # Log the command, replacing \$HOME for readability in the log
  echo "$git_commands" | sed "s/\\\$HOME/~/" >> "$logfile"
  echo "--- Remote Output ---" >> "$logfile"

  # Execute the command sequence via SSH, append output to log
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$host" "$git_commands" >> "$logfile" 2>&1
  local ssh_status=$? # Capture the exit status of the *entire* sequence

  # --- Report Result based on SSH exit status ---
  if [ $ssh_status -eq 0 ]; then
    echo "[ OK ] Git commands completed successfully on $host." >> "$logfile"
    return 0 # Success
  else
    # Check for specific exit codes we defined
    local reason=""
    case $ssh_status in
      10) reason="(Commit Failed)" ;;
      11) reason="(Branch Creation/Checkout Failed)" ;;
      12) reason="(Push Failed)" ;;
       *) reason="(Unknown Git Error - Exit Status: $ssh_status)" ;;
    esac
    echo "[FAIL] Git commands failed on $host $reason. Check log for details." >> "$logfile"
    return 3 # Git Command Failure (use a distinct code)
  fi
}

# --- Main Execution Logic ---
pids=()

echo "Launching Git sync process for ${#MACHINE_NAME_LIST[@]} hosts (Max parallel: $MAX_PARALLEL)..."

# Process hosts in parallel, redirecting output
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

  # Launch in background
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
    # Print the captured output for this host
    cat "$log_file"
    echo # Add a blank line between host outputs

    # Determine status by searching the log file content
    if grep -q "\[ OK \] Git commands completed successfully" "$log_file"; then
      successful_hosts+=("$host")
    elif grep -q "\[FAIL\] Connection failed" "$log_file"; then
      conn_failed_hosts+=("$host")
    elif grep -q "\[FAIL\] Git commands failed" "$log_file"; then
      # Extract reason if possible
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

#!/usr/bin/env bash
# Be tolerant of per-host errors; do not exit on first failure
set -u

# --- Args ---
if [ $# -eq 0 ]; then
  echo 'ERROR: backup label argument required (e.g., "w0d1")'
  echo "Example: $0 w0d1"
  exit 1
fi
LABEL="$1"
echo "$LABEL"

# --- Configuration (from ../config.env) ---
source "$(dirname "$0")/../config.env"

SSH_KEY="$SHARED_SSH_KEY_PATH"

# User for SSH connection (align with sync_git.sh)
SSH_USER="root"

# Max number of parallel processes
MAX_PARALLEL=10

# Max size per file to sync (can be overridden via env)
MAX_SIZE="${MAX_SIZE:-50M}"

# Remote base to pull from
REMOTE_HOME="~"

# SSH options (align with sync_git.sh)
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

# --- Logging ---
LOG_DIR="$(dirname "$0")/../logs"
TMP_LOG_DIR="$LOG_DIR/tmp_cp_logs"
mkdir -p "$TMP_LOG_DIR"

# --- Per-host processing ---
process_host() {
  local nato_name="$1"
  local host="$MACHINE_NAME_PREFIX-$nato_name"
  local logfile="$TMP_LOG_DIR/log_$nato_name.log"
  local input_folder="$SSH_USER@$host:$REMOTE_HOME/"
  local output_folder="./backup/$LABEL/$host"

  {
    echo "=== Copying from $host ==="
    echo "Label: $LABEL"
    echo "Input: $input_folder"
    echo "Output: $output_folder"
    echo "--- [1/3] Testing SSH connectivity ---"
  } >> "$logfile"

  if ! ssh "${SSH_CONNECT_TEST_OPTS[@]}" "$SSH_USER@$host" exit; then
    echo "[FAIL] Connection failed or timed out." >> "$logfile"
    return 1 # Connection Failure
  fi
  echo "Connection OK." >> "$logfile"

  mkdir -p "$output_folder"

  {
    echo "--- [2/3] Running rsync ---"
    echo "rsync options: -avz --human-readable --info=progress2 --max-size=$MAX_SIZE"
    echo "Excludes: **/.*/ , site-packages/"
  } >> "$logfile"

  # Build ssh command string for rsync
  local ssh_cmd="ssh -i \"$SSH_KEY\" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=30"

  # ACTUAL COMMAND HERE
  #####################
  if rsync -avz --human-readable --info=progress2 \
      --max-size="$MAX_SIZE" \
      --exclude='**/.*/' --exclude="site-packages/" \
      --prune-empty-dirs \
      -e "$ssh_cmd" \
      "$input_folder" "$output_folder" >> "$logfile" 2>&1; then
    echo "--- [3/3] Rsync finished." >> "$logfile"
    echo "[ OK ] Copy completed successfully on $host." >> "$logfile"
    return 0
  else
    echo "--- [3/3] Rsync failed." >> "$logfile"
    echo "[FAIL] Rsync failed on $host." >> "$logfile"
    return 2 # Rsync Failure
  fi
}

# --- Main Execution ---
pids=()

echo "Launching copy process for ${#MACHINE_NAME_LIST[@]} hosts (Max parallel: $MAX_PARALLEL)..."

for name in "${MACHINE_NAME_LIST[@]}"; do
  log_file="$TMP_LOG_DIR/log_$name.log"

  # Throttle parallel jobs
  if [ ${#pids[@]} -ge $MAX_PARALLEL ]; then
    wait -n "${pids[@]}"
    new_pids=()
    for pid_chk in "${pids[@]}"; do
      if kill -0 "$pid_chk" 2>/dev/null; then new_pids+=("$pid_chk"); fi
    done
    pids=("${new_pids[@]}")
  fi

  # Launch in background with per-host log
  process_host "$name" > "$log_file" 2>&1 &
  pids+=($!)
done

echo "Waiting for remaining processes (${#pids[@]}) to finish..."
wait

echo "All processes finished. Consolidating results..."
echo

# --- Consolidated Output & Summary ---
successful_hosts=()
conn_failed_hosts=()
copy_failed_hosts=()

for name in "${MACHINE_NAME_LIST[@]}"; do
  host="${MACHINE_NAME_PREFIX}-$name"
  log_file="$TMP_LOG_DIR/log_$name.log"
  if [ -f "$log_file" ]; then
    # Print the captured output for this host
    cat "$log_file"
    echo

    if grep -q "\[ OK \] Copy completed successfully" "$log_file"; then
      successful_hosts+=("$host")
    elif grep -q "\[FAIL\] Connection failed" "$log_file"; then
      conn_failed_hosts+=("$host")
    elif grep -q "\[FAIL\] Rsync failed" "$log_file"; then
      copy_failed_hosts+=("$host")
    else
      copy_failed_hosts+=("$host (Unknown Error/State)")
    fi
  else
    conn_failed_hosts+=("$host (Log file missing)")
  fi
done

echo "--- Summary ---"
echo "Label: $LABEL"
echo "Total hosts processed: ${#MACHINE_NAME_LIST[@]}"
echo
echo "[ OK ] Successful Hosts (${#successful_hosts[@]}):"
if [ ${#successful_hosts[@]} -gt 0 ]; then printf "  %s\n" "${successful_hosts[@]}"; else echo "  None"; fi
echo
echo "[FAIL] Connection Failed Hosts (${#conn_failed_hosts[@]}):"
if [ ${#conn_failed_hosts[@]} -gt 0 ]; then printf "  %s\n" "${conn_failed_hosts[@]}"; else echo "  None"; fi
echo
echo "[FAIL] Rsync Failed Hosts (${#copy_failed_hosts[@]}):"
if [ ${#copy_failed_hosts[@]} -gt 0 ]; then printf "  %s\n" "${copy_failed_hosts[@]}"; else echo "  None"; fi
echo "---------------"

echo "Individual logs are in $TMP_LOG_DIR"

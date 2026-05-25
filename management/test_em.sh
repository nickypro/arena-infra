#!/usr/bin/env bash

# --- Configuration ---
# Load config.env from parent directory
source "$(dirname "$0")/../config.env"

# The Python code to run
PYTHON_CODE='import torch; print(f"Torch version: {torch.__version__}, Tensor: {torch.tensor([0.1])}")'

# SSH options to reduce noise and avoid prompts
SSH_OPTS=(
  -o ConnectTimeout=15      # Timeout for the command execution
  -o StrictHostKeyChecking=no # Don't ask about host keys
  -o UserKnownHostsFile=/dev/null # Don't store host keys
  -o LogLevel=ERROR         # Suppress warnings like adding host keys
  -i "$SHARED_SSH_KEY_PATH"             # Use the specified key
)
SSH_CONNECT_TEST_OPTS=(
  -q                        # Quiet mode for connection test
  -o BatchMode=yes          # Never ask for password/passphrase
  -o ConnectTimeout=5       # Shorter timeout for just the connection test
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -i "$SHARED_SSH_KEY_PATH"
)
# --- End Configuration ---

# NATO phonetic alphabet array
# MACHINE_NAME_LIST=(
#   "alpha" "bravo" "charlie" "delta" "echo" "foxtrot" "golf" "hotel"
#   "india" "juliett" "kilo" "lima" "mike" "november" "oscar" "papa"
#   "quebec" "romeo" "sierra" "tango" "uniform" "victor" "whiskey"
#   "xray" "yankee" "zulu"
# )

# Temporary directory for logs
TMP_LOG_DIR="./logs/tmp_torch_check_logs"
mkdir -p "$TMP_LOG_DIR"

# Function to process a single host
# This function's output will be redirected to a file
process_host() {
  local nato_name="$1"
  local host="$MACHINE_NAME_PREFIX-$nato_name"
  local status_code=0 # 0=OK, 1=ConnectionFail, 2=CommandFail

  echo "--- Processing $host ---"

  # --- Connection Test ---
  if ! ssh "${SSH_CONNECT_TEST_OPTS[@]}" "$host" exit; then
    echo "[FAIL] Connection failed or timed out."
    status_code=1
  else
    # --- Construct and Execute the Command via SSH ---
    local output
    local ssh_status
    # Use the full path to conda, pass the python code in single quotes
    output=$(ssh "${SSH_OPTS[@]}" "$host" \
      "/opt/conda/bin/conda run --no-capture-output -n \"$CONDA_ENV_NAME\" python3 -c '$PYTHON_CODE'" 2>&1)
    ssh_status=$?

    # --- Report Result ---
    if [ $ssh_status -eq 0 ]; then
      echo "[ OK ] Success!"
      echo "       Output:"
      # Indent the captured output for readability
      echo "$output" | sed 's/^/         /'
      status_code=0
    else
      echo "[FAIL] Command failed (Exit Status: $ssh_status)."
      echo "       Error/Output:"
      echo "$output" | sed 's/^/         /'
      status_code=2
    fi
  fi
  # Return the status code for summary purposes
  return $status_code
}

# --- Main Execution Logic ---
pids=()
host_status=() # Array to store final status (OK, CONN_FAIL, CMD_FAIL)

echo "Launching checks for ${#MACHINE_NAME_LIST[@]} hosts (Max parallel: $MAX_PARALLEL)..."

# Process hosts in parallel, redirecting output
for i in "${!MACHINE_NAME_LIST[@]}"; do
  name="${MACHINE_NAME_LIST[$i]}"
  host="$MACHINE_NAME_PREFIX-$name"
  log_file="$TMP_LOG_DIR/log_$name.log"

  if [ ${#pids[@]} -ge $MAX_PARALLEL ]; then
    # Wait for any process to finish and record its status
    wait -n "${pids[@]}" # Wait for any PID in the list
    finished_pid=$?
    # Find which host finished and store its status (more robust needed if wait -n isn't available/reliable)
    # Simple approach: just clean up the general pids list
    new_pids=()
    for pid_chk in "${pids[@]}"; do
        if kill -0 "$pid_chk" 2>/dev/null; then
            new_pids+=("$pid_chk")
        fi
    done
    pids=("${new_pids[@]}")
  fi

  # Launch in background, redirecting stdout/stderr to the log file
  process_host "$name" > "$log_file" 2>&1 &
  pids+=($!)
  # Store mapping from PID to host name if needed for more complex status tracking
done

# Wait for all remaining background processes
echo "Waiting for remaining processes (${#pids[@]}) to finish..."
wait # Wait for all remaining PIDs

echo "All processes finished. Consolidating results..."
echo # Blank line for spacing

# --- Consolidate and Print Results ---
successful_hosts=()
connection_failed_hosts=()
command_failed_hosts=()

for name in "${MACHINE_NAME_LIST[@]}"; do
  host="$MACHINE_NAME_PREFIX-$name"
  log_file="$TMP_LOG_DIR/log_$name.log"
  if [ -f "$log_file" ]; then
    # Print the captured output for this host
    cat "$log_file"
    echo # Add a blank line between host outputs

    # Determine status by searching the log file content
    if grep -q "\[ OK \]" "$log_file"; then
      successful_hosts+=("$host")
    elif grep -q "\[FAIL\] Connection failed" "$log_file"; then
      connection_failed_hosts+=("$host")
    elif grep -q "\[FAIL\] Command failed" "$log_file"; then
      command_failed_hosts+=("$host")
    else
      # Fallback if log format is unexpected
      command_failed_hosts+=("$host (Unknown Error)")
    fi
  else
    # Should not happen if script runs correctly
    connection_failed_hosts+=("$host (Log file missing)")
  fi
done

# --- Final Summary ---
echo "--- Summary ---"
echo "Total hosts processed: ${#MACHINE_NAME_LIST[@]}"
echo
echo "[ OK ] Successful Hosts (${#successful_hosts[@]}):"
if [ ${#successful_hosts[@]} -gt 0 ]; then printf "  %s\n" "${successful_hosts[@]}"; else echo "  None"; fi
echo
echo "[FAIL] Connection Failed Hosts (${#connection_failed_hosts[@]}):"
if [ ${#connection_failed_hosts[@]} -gt 0 ]; then printf "  %s\n" "${connection_failed_hosts[@]}"; else echo "  None"; fi
echo
echo "[FAIL] Command Failed Hosts (${#command_failed_hosts[@]}):"
if [ ${#command_failed_hosts[@]} -gt 0 ]; then printf "  %s\n" "${command_failed_hosts[@]}"; else echo "  None"; fi
echo "---------------"

# --- Cleanup ---
# rm -rf "$TMP_LOG_DIR"
echo "Individual logs are in $TMP_LOG_DIR" # Keep logs for inspection

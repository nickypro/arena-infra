#!/bin/bash

# Load config.env from parent directory
source "$(dirname "$0")/../config.env"
logdir="$(dirname "$0")/../logs"

# --- Configuration ---
# SSH key to use for connecting to the pods
SSH_KEY_PATH=$SHARED_SSH_KEY_PATH
# Local path to the private SSH key that will be copied TO the pods for Git operations
GIT_SSH_KEY_LOCAL=$SHARED_SSH_KEY_PATH

# User for SSH connection (should be 'root' as per your Docker setup)
SSH_USER="root"
# Remote path where the GIT_SSH_KEY_LOCAL will be copied on the pod
GIT_SSH_KEY_REMOTE=${SHARED_SSH_KEY_PATH:="/root/.ssh/id_ed25519"}

# ARENA Repository details (ensure this matches what was cloned in Docker)
# If you used ARENA_REPO_ARG in Docker build, adjust this accordingly.
ARENA_REMOTE_SSH_URL="git@github.com:${ARENA_REPO_OWNER}/${ARENA_REPO_NAME}.git"
ARENA_REPO_PATH="/root/${ARENA_REPO_NAME}" # Path where the repo is cloned in the Docker image
DEFAULT_BRANCH="main" # Or "master", or use `git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'`

# Max number of parallel processes
MAX_PARALLEL=10


# --- End Configuration ---

# Ensure logs directory exists
mkdir -p $logdir

# Function to process a single host
process_host() {
  local machine_name="$1"
  local pod_hostname="${MACHINE_NAME_PREFIX}-${machine_name}" # Assuming this is how your pods are named/accessible
  local logfile="$logdir/init-${pod_hostname}.log"

  echo "--- Starting setup for ${pod_hostname} ---" > "$logfile"
  date >> "$logfile"

  # 1. Test SSH Connection to the Pod
  echo "[${pod_hostname}] Testing SSH connection..." | tee -a "$logfile"
  if ! ssh -q -o BatchMode=yes -o ConnectTimeout=10 -i "$SSH_KEY_PATH" "${SSH_USER}@${pod_hostname}" exit; then
    echo "[${pod_hostname}] ERROR: SSH connection failed. Skipping." | tee -a "$logfile"
    echo "[SKIP] ${pod_hostname} (Connection failed)"
    return 1
  fi
  echo "[${pod_hostname}] SSH connection successful." | tee -a "$logfile"

  # 2. Copy the dedicated Git SSH key to the pod
  echo "[${pod_hostname}] Copying Git SSH key to ${GIT_SSH_KEY_REMOTE}..." | tee -a "$logfile"
  scp -i "$SSH_KEY_PATH" -o ConnectTimeout=10 "$GIT_SSH_KEY_LOCAL" "${SSH_USER}@${pod_hostname}:${GIT_SSH_KEY_REMOTE}" >> "$logfile" 2>&1
  if [ $? -ne 0 ]; then
    echo "[${pod_hostname}] ERROR: Failed to copy Git SSH key." | tee -a "$logfile"
    echo "[FAIL] ${pod_hostname} (scp key)"
    return 1
  fi

  ssh -i "$SSH_KEY_PATH" "${SSH_USER}@${pod_hostname}" "chmod 600 ${GIT_SSH_KEY_REMOTE}" >> "$logfile" 2>&1
  if [ $? -ne 0 ]; then
    echo "[${pod_hostname}] ERROR: Failed to chmod Git SSH key on pod." | tee -a "$logfile"
    echo "[FAIL] ${pod_hostname} (chmod key)"
    return 1
  fi
  echo "[${pod_hostname}] Git SSH key copied and permissions set." | tee -a "$logfile"
  # 3. Ensure /root/.ssh/config has a github.com host block using the copied key
  echo "[${pod_hostname}] Ensuring SSH config for github.com is set..." | tee -a "$logfile"
  
  # Create SSH config commands (broken down for readability)
  local ssh_config_commands="
    mkdir -p /root/.ssh && 
    touch /root/.ssh/config && 
    chmod 700 /root/.ssh && 
    sed -i '/^# BEGIN arena-infra github.com/,/^# END arena-infra github.com/d' /root/.ssh/config && 
    printf '%s\n' \
      '# BEGIN arena-infra github.com' \
      'Host github.com' \
      '    AddKeysToAgent yes' \
      '    IdentityFile ${GIT_SSH_KEY_REMOTE}' \
      '# END arena-infra github.com' \
      >> /root/.ssh/config && 
    chmod 600 /root/.ssh/config
  "
  
  ssh -i "$SSH_KEY_PATH" "${SSH_USER}@${pod_hostname}" "$ssh_config_commands" >> "$logfile" 2>&1
  if [ $? -ne 0 ]; then
    echo "[${pod_hostname}] ERROR: Failed to update SSH config on pod." | tee -a "$logfile"
    echo "[FAIL] ${pod_hostname} (ssh config)"
    return 1
  fi
  echo "[${pod_hostname}] SSH config updated for github.com." | tee -a "$logfile"

  # 4. Configure Git remote for SSH and pull updates
  echo "[${pod_hostname}] Configuring Git remote for SSH and pulling updates from ${DEFAULT_BRANCH}..." | tee -a "$logfile"
  # Ensure GitHub is in known_hosts (Docker image should do this, but good to be safe or re-verify)
  # ssh -i "$SSH_KEY_PATH" "${SSH_USER}@${pod_hostname}" "ssh-keyscan -t rsa github.com >> /root/.ssh/known_hosts" >> "$logfile" 2>&1

  # Commands to run on the remote pod
  # - Navigate to the repository
  # - Set the remote URL to the SSH version
  # - Fetch updates from origin
  # - Reset to the latest from the specified branch (handles diverged histories if any, use with care)
  #   Alternatively, use 'git pull origin ${DEFAULT_BRANCH}' if you prefer a merge or rebase strategy.
  #   'git checkout ${DEFAULT_BRANCH} && git reset --hard origin/${DEFAULT_BRANCH}' is a forceful way to match the remote.
  #   A simple 'git pull origin ${DEFAULT_BRANCH}' is often sufficient.
  local git_commands="cd \"${ARENA_REPO_PATH}\" && \
git remote set-url origin \"${ARENA_REMOTE_SSH_URL}\" && \
echo 'Remote URL set to SSH.' && \
git fetch origin && \
echo 'Fetched from origin.' && \
git checkout \"${DEFAULT_BRANCH}\" && \
echo 'Checked out ${DEFAULT_BRANCH}.' && \
git reset --hard \"origin/${DEFAULT_BRANCH}\" && \
echo 'Reset to origin/${DEFAULT_BRANCH}.' && \
git submodule update --init --recursive && \
echo 'Updated submodules.'"
# Using git reset --hard ensures the local matches the remote branch exactly.
# If you have local changes you don't want to lose, this is destructive.
# For CI/CD or fresh setups, it's often desired.

  ssh -i "$SSH_KEY_PATH" "${SSH_USER}@${pod_hostname}" "${git_commands}" >> "$logfile" 2>&1
  if [ $? -ne 0 ]; then
    echo "[${pod_hostname}] ERROR: Failed to set Git remote or pull updates." | tee -a "$logfile"
    echo "[FAIL] ${pod_hostname} (git ops)"
    # Optionally return 1 here if this is critical
  else
    echo "[${pod_hostname}] Git remote configured and repository updated." | tee -a "$logfile"
  fi

  # 5. Add/Update the .name file
  echo "[${pod_hostname}] Creating/Updating /root/.name file..." | tee -a "$logfile"
  ssh -i "$SSH_KEY_PATH" "${SSH_USER}@${pod_hostname}" "echo \"export MACHINE_NAME='${machine_name}'\" > /root/.name" >> "$logfile" 2>&1
  if [ $? -ne 0 ]; then
    echo "[${pod_hostname}] ERROR: Failed to create /root/.name file." | tee -a "$logfile"
    echo "[FAIL] ${pod_hostname} (.name file)"
    # Optionally return 1
  else
    echo "[${pod_hostname}] /root/.name file created with MACHINE_NAME=${machine_name}." | tee -a "$logfile"
  fi

  # 5. (Optional) Re-run MOTD script if it depends on .name file and doesn't run on every login
  # echo "[${pod_hostname}] Re-generating MOTD..." | tee -a "$logfile"
  # ssh -i "$SSH_KEY_PATH" "${SSH_USER}@${pod_hostname}" "bash /root/.arena_dotfiles/motd.sh" >> "$logfile" 2>&1

  echo "[${pod_hostname}] Setup completed." | tee -a "$logfile"
  echo "[DONE] ${pod_hostname}"
}

# --- Main Execution Logic ---
# Check if GIT_SSH_KEY_LOCAL exists
if [ ! -f "$GIT_SSH_KEY_LOCAL" ]; then
  echo "ERROR: Git SSH key for pods not found at $GIT_SSH_KEY_LOCAL"
  stat "$GIT_SSH_KEY_LOCAL"
  echo "Please create it or update GIT_SSH_KEY_LOCAL path."
  exit 1
fi

# Check if SSH_KEY_PATH for connecting exists
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "ERROR: SSH key for connecting to pods not found at $SSH_KEY_PATH"
  echo "Please create it or update SSH_KEY_PATH."
  exit 1
fi


active_pids=()
for machine_name_suffix in "${MACHINE_NAME_LIST[@]}"; do
  process_host "$machine_name_suffix" &
  active_pids+=($!)

  # Limit parallel processes
  if [ ${#active_pids[@]} -ge $MAX_PARALLEL ]; then
    wait -n # Wait for any process to finish
    # Remove completed PIDs from the array
    temp_pids=()
    for pid in "${active_pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then # Check if PID is still running
        temp_pids+=("$pid")
      fi
    done
    active_pids=("${temp_pids[@]}")
  fi
done

# Wait for all remaining background processes to complete
echo "Waiting for all pod setup processes to complete: ${active_pids[@]}"
wait
echo "All pod setup processes finished."

# Optional: Combine all logs into one file
echo "Combining logs..."
cat $logdir/init-${MACHINE_NAME_PREFIX}-*.log > $logdir/init-all-pods.log 2>/dev/null
echo "Combined log saved to ./logs/init-all-pods.log"

echo "--- All Pods Processed ---"

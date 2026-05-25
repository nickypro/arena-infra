#!/usr/bin/env bash
#
# =============================================================================
# setup_em.sh - Initialize ARENA pods with SSH keys and Git configuration
# =============================================================================
#
# TLDR: Sets up multiple pods in parallel with Git access and machine identity.
#
# WHAT IT DOES:
#   For each machine in MACHINE_NAME_LIST (from config.env), this script:
#     1. Tests SSH connectivity to the pod
#     2. Copies a Git SSH key to enable GitHub access
#     3. Configures ~/.ssh/config for github.com
#     4. Sets the ARENA repo remote to SSH and pulls latest from main
#     5. Creates /root/.name with the machine's identity (MACHINE_NAME)
#
# USAGE:
#   ./setup_em.sh [--force]
#
# OPTIONS:
#   --force    Force checkout to main branch (default: stay on current branch)
#
# EXAMPLE:
#   # With config.env containing:
#   #   MACHINE_NAME_LIST=("alice" "bob" "charlie")
#   #   MACHINE_NAME_PREFIX="arena-pod"
#   #
#   # The script will configure pods:
#   #   arena-pod-alice, arena-pod-bob, arena-pod-charlie
#   #
#   # Each pod gets:
#   #   - SSH key at /root/.ssh/id_ed25519
#   #   - Git remote set to git@github.com:OWNER/REPO.git
#   #   - /root/.name containing: export MACHINE_NAME='alice'
#
# LOGS:
#   Individual: ./logs/init-arena-pod-<name>.log
#   Combined:   ./logs/init-all-pods.log
#
# =============================================================================

# --- Argument Parsing ---
FORCE_CHECKOUT=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --force)
      FORCE_CHECKOUT=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--force]"
      exit 1
      ;;
  esac
done

# Load config.env from parent directory
source "$(dirname "$0")/../config.env"
logdir="$(dirname "$0")/../logs"

# --- Configuration ---
# SSH key to use for connecting to the pods
SSH_KEY_PATH=$SHARED_SSH_KEY_PATH
# Local path to the private SSH key that will be copied TO the pods for Git operations
GIT_SSH_KEY_LOCAL=${GIT_SSH_KEY_LOCAL:-"/root/.ssh/arena_infra_key"}

# User for SSH connection (should be 'root' as per your Docker setup)
SSH_USER="root"
# Remote path where the GIT_SSH_KEY_LOCAL will be copied on the pod
GIT_SSH_KEY_REMOTE=${GIT_SSH_KEY_REMOTE:-"/root/.ssh/id_ed25519"}

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
  local force_checkout="$2"
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
  if [ "$force_checkout" = "true" ]; then
    echo "[${pod_hostname}] Configuring Git remote for SSH and forcing checkout to ${DEFAULT_BRANCH}..." | tee -a "$logfile"
  else
    echo "[${pod_hostname}] Configuring Git remote for SSH and pulling updates (staying on current branch)..." | tee -a "$logfile"
  fi
  # Ensure GitHub is in known_hosts (Docker image should do this, but good to be safe or re-verify)
  # ssh -i "$SSH_KEY_PATH" "${SSH_USER}@${pod_hostname}" "ssh-keyscan -t rsa github.com >> /root/.ssh/known_hosts" >> "$logfile" 2>&1

  # Commands to run on the remote pod
  # - Navigate to the repository
  # - Set the remote URL to the SSH version
  # - Fetch updates from origin
  # - If --force: checkout to main and reset hard
  # - If not --force: stay on current branch, pull if on main, otherwise just pull
  local git_commands
  if [ "$force_checkout" = "true" ]; then
    git_commands="cd \"${ARENA_REPO_PATH}\" && \
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
  else
    # Stay on current branch, update accordingly
    git_commands="cd \"${ARENA_REPO_PATH}\" && \
git remote set-url origin \"${ARENA_REMOTE_SSH_URL}\" && \
echo 'Remote URL set to SSH.' && \
git fetch origin && \
echo 'Fetched from origin.' && \
CURRENT_BRANCH=\$(git rev-parse --abbrev-ref HEAD) && \
echo \"Current branch: \$CURRENT_BRANCH\" && \
if [ \"\$CURRENT_BRANCH\" = \"${DEFAULT_BRANCH}\" ]; then \
  git reset --hard \"origin/${DEFAULT_BRANCH}\" && \
  echo 'Reset to origin/${DEFAULT_BRANCH}.'; \
else \
  git pull && \
  echo 'Pulled latest changes.'; \
fi && \
git submodule update --init --recursive && \
echo 'Updated submodules.'"
  fi
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

if [ "$FORCE_CHECKOUT" = "true" ]; then
  echo "Running with --force: will checkout to ${DEFAULT_BRANCH} branch on all pods."
else
  echo "Running without --force: will stay on current branch (update to latest if on ${DEFAULT_BRANCH})."
fi

active_pids=()
for machine_name_suffix in "${MACHINE_NAME_LIST[@]}"; do
  process_host "$machine_name_suffix" "$FORCE_CHECKOUT" &
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

# ------------------------------------------------------------
# COMMANDS RUN (per pod):
#   # 1. Test SSH connection
#   ssh -i $SSH_KEY_PATH root@<pod> exit
#
#   # 2. Copy Git SSH key
#   scp -i $SSH_KEY_PATH $GIT_SSH_KEY_LOCAL root@<pod>:/root/.ssh/id_ed25519
#   ssh ... "chmod 600 /root/.ssh/id_ed25519"
#
#   # 3. Configure SSH for GitHub
#   ssh ... "mkdir -p /root/.ssh && \
#            sed -i '/^# BEGIN arena-infra/,/^# END arena-infra/d' /root/.ssh/config && \
#            printf 'Host github.com\n  IdentityFile /root/.ssh/id_ed25519\n' >> /root/.ssh/config"
#
#   # 4. Pull latest code (behavior depends on --force flag)
#   # Without --force: stay on current branch, reset if on main, pull otherwise
#   # With --force: checkout to main and reset hard
#   ssh ... "cd /root/ARENA && \
#            git remote set-url origin git@github.com:OWNER/REPO.git && \
#            git fetch origin && \
#            # if --force: git checkout main && git reset --hard origin/main
#            # else: stay on branch, reset if main, pull if other
#            git submodule update --init --recursive"
#
#   # 5. Set machine identity
#   ssh ... "echo \"export MACHINE_NAME='alice'\" > /root/.name"
# ------------------------------------------------------------

#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

ARENA_REPO="${1:-styme3279/ARENA_3.0}" # Default if no arg passed

echo "--- Starting Main Environment Setup ---"
echo "ARENA Repository: ${ARENA_REPO}"

# --- System Package Installation (Non-Zsh specific) ---
echo "Updating and installing system packages..."
apt-get update -y
apt-get install -y --no-install-recommends \
    ncdu vim nano htop net-tools iputils-ping tree ffmpeg sudo fzf nvtop \
    figlet curl wget git ca-certificates \
    build-essential # For potential pip packages that need compilation

# --- Miniconda Setup ---
echo "Installing Miniconda..."
wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
bash /tmp/miniconda.sh -b -p /opt/conda
rm /tmp/miniconda.sh
export PATH="/opt/conda/bin:$PATH" # Add conda to PATH for this script

# add ffmpeg
rm -f /opt/conda/bin/ffmpeg # Remove conda's ffmpeg if it exists
ln -s /usr/bin/ffmpeg /opt/conda/bin/ffmpeg # Or ensure /usr/bin is prioritized

echo "Initializing Conda for bash..." # Zsh init will be handled by zsh_setup.sh
conda init bash

# Source conda for current script session to use conda commands
# shellcheck disable=SC1091
source /opt/conda/etc/profile.d/conda.sh

# --- ARENA Environment Setup ---
echo "Creating and setting up 'arena-env' Conda environment..."
conda create -n arena-env python=3.10 -y
conda activate arena-env # Activate for subsequent commands in this script layer

echo "Cloning ARENA_3.0 repository..."
git clone "https://github.com/${ARENA_REPO}.git" /root/ARENA_3.0

echo "Installing ARENA_3.0 Python requirements..."
if [ -f /root/ARENA_3.0/requirements.txt ]; then
    pip install --no-cache-dir -r /root/ARENA_3.0/requirements.txt
else
    echo "Warning: /root/ARENA_3.0/requirements.txt not found."
fi

# --- SSH and Other Configurations ---
echo "Adding GitHub to known_hosts..."
mkdir -p /root/.ssh
ssh-keyscan github.com >> /root/.ssh/known_hosts
chmod 600 /root/.ssh/known_hosts

echo "Touching /root/.no_auto_tmux..."
touch /root/.no_auto_tmux

# get mujoco files pls
cd ~
wget https://mujoco.org/download/mujoco210-linux-x86_64.tar.gz
tar -xzf mujoco210-linux-x86_64.tar.gz
mkdir ~/.mujoco
mv ./mujoco210 ~/.mujoco/mujoco210

pip install mujoco free-mujoco-py
apt-get install -y libgl1-mesa-dev libgl1-mesa-glx libglew-dev libosmesa6-dev software-properties-common
apt-get install -y patchelf

echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/root/.mujoco/mujoco210/bin" >> ~/.bashrc


echo "--- Main Environment Setup Complete ---"



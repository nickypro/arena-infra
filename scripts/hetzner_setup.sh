#!/usr/bin/env bash
# Provision a bare Hetzner Ubuntu 24.04 x86 VM to look like an ARENA pod:
#   - system deps (build tools, ffmpeg, libosmesa6 for headless mujoco, zsh, …)
#   - docker + docker compose
#   - uv + a Python 3.11 venv with the ARENA packages (CPU substitutions)
#   - a ~/.zshrc / ~/.bashrc that auto-activates the venv, so `arena pods run`
#     (which does `zsh -c 'source ~/.zshrc; …'`) lands in the right Python.
#
# The arena8 SSH key is attached at CREATE time by the provider (MACHINE_NAME_PREFIX),
# so this script assumes you can already SSH in. Run as root on the pod:
#   ssh arena8-<name> 'bash -s' < hetzner_setup.sh
# Idempotent-ish: safe to re-run.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

REPO_DIR="${REPO_DIR:-/root/ARENA_3.0}"
# If the repo isn't already present (e.g. rsync'd from the control plane), clone it.
REPO_URL="${REPO_URL:-https://github.com/callummcdougall/ARENA_3.0.git}"
VENV="$REPO_DIR/.venv"

echo "### 1/5 system packages"
apt-get update -qq
apt-get install -y --no-install-recommends \
    build-essential ffmpeg git curl wget ca-certificates libosmesa6 jq zsh \
    python3-dev pkg-config

echo "### 2/5 docker + docker compose"
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker 2>/dev/null || true
docker --version
docker compose version || echo "WARN: docker compose plugin missing"

echo "### 3/5 uv"
if ! command -v uv >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/uv" ]; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"
uv --version

echo "### 4/5 ARENA_3.0 + Python env"
[ -d "$REPO_DIR" ] || git clone --depth 1 "$REPO_URL" "$REPO_DIR"
cd "$REPO_DIR"
# CPU substitutions: torch CPU wheels instead of CUDA, jax[cpu] instead of jax[cuda12].
sed -e 's#https://download.pytorch.org/whl/cu118#https://download.pytorch.org/whl/cpu#' \
    -e 's#^jax\[cuda12\]#jax[cpu]#' \
    requirements.txt > requirements.cpu.txt
# transformer_lens pins numpy<2, which conflicts with jax (numpy>=2). That pin is stale —
# override it so the resolve succeeds (TL runs fine on numpy 2.x).
printf 'numpy>=2.0\n' > overrides.txt
uv venv --python 3.11 "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
# --index-strategy unsafe-best-match: the torch CPU extra-index also carries some shared
# deps (e.g. importlib-metadata) at versions that conflict with PyPI pins (circuitsvis);
# this lets uv pick the best version across BOTH indexes instead of first-index-only.
uv pip install --no-cache-dir --index-strategy unsafe-best-match \
    --override overrides.txt -r requirements.cpu.txt

echo "### 5/5 shell rc (auto-activate the venv for arena pods run)"
ACT="source $VENV/bin/activate 2>/dev/null"
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    touch "$rc"
    grep -qF "$ACT" "$rc" || printf '\n# ARENA venv (added by hetzner_setup.sh)\n%s\n' "$ACT" >> "$rc"
done
# Tokens (OPENROUTER_API_KEY, HF_TOKEN, …) are distributed separately by
# `arena pods copy-keys` (cross-provider), which appends exports to these same rc files.

echo "### done — $(python --version 2>&1), torch $(python -c 'import torch; print(torch.__version__)' 2>/dev/null || echo '?')"

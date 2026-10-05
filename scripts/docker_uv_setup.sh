#!/bin/bash
# Provision the ARENA GPU container with a uv-based Python env (replaces conda).
#
# Follows the course repo's own install.sh (python 3.13 env, plain `pip install -r
# requirements.txt`, arena-llm-context clone, VS Code settings), with uv + a venv at
# /opt/arena-env instead of conda. On top of that it bakes in what a pod needs offline:
# system packages, every external subrepo the chapters clone, and the claude/codex CLIs.
set -euo pipefail

ARENA_REPO="${1:-ARENA-education/ARENA_materials}"
ARENA_BRANCH="${2:-main}"
# Checkout dir follows the repo name (ARENA-education/ARENA_materials -> /root/ARENA_materials).
REPO_DIR="${REPO_DIR:-/root/${ARENA_REPO##*/}}"
VENV="${VENV:-/opt/arena-env}"
LLM_CONTEXT_REPO="callummcdougall/arena-llm-context"

echo "=== docker_uv_setup: repo=${ARENA_REPO}@${ARENA_BRANCH} dir=${REPO_DIR} venv=${VENV} ==="

# --- System packages (same set as the conda docker_setup.sh + headless-render libosmesa6) ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    ncdu vim nano htop net-tools iputils-ping tree ffmpeg sudo fzf nvtop \
    figlet curl wget git ca-certificates btop rsync lsof tmux zip unzip \
    build-essential libosmesa6 jq pkg-config zsh

# --- uv ---
echo "=== Installing uv ==="
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="/root/.local/bin:$PATH"
# Make uv available to every later login shell as well.
ln -sf /root/.local/bin/uv  /usr/local/bin/uv
ln -sf /root/.local/bin/uvx /usr/local/bin/uvx 2>/dev/null || true
uv --version

# --- Clone the ARENA course repo ---
echo "=== Cloning ${ARENA_REPO}@${ARENA_BRANCH} -> ${REPO_DIR} ==="
[ -d "$REPO_DIR" ] || git clone -b "$ARENA_BRANCH" "https://github.com/${ARENA_REPO}.git" "$REPO_DIR"
# Fleet tooling (backup, set-branch, ARENA_REPO_NAME default) still assumes /root/ARENA_3.0;
# keep that path working when the repo is checked out under a different name.
[ "$REPO_DIR" = /root/ARENA_3.0 ] || [ -e /root/ARENA_3.0 ] || ln -s "$REPO_DIR" /root/ARENA_3.0

# --- arena-env virtualenv (uv) ---
# Mirrors the Python half of the repo's install.sh (python 3.13, upgrade pip/setuptools/wheel,
# then a plain `-r requirements.txt`) with uv in place of conda + pip. requirements.txt carries
# its own fixes now (ARENA forks of sae-vis/eindex, numpy>=2-compatible transformer_lens, CUDA
# torch from PyPI), so no overrides or extra indexes here — if this resolve breaks, fix it
# upstream rather than patching around it in the image.
echo "=== Creating uv venv arena-env (python 3.13) at ${VENV} ==="
uv venv --python 3.13 "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"

# `uv venv` doesn't ship pip; installing it (as install.sh upgrades it) means bare `pip` /
# `pip show <pkg>` operate on arena-env without a `uv ` prefix.
echo "=== Installing pip/setuptools/wheel into arena-env ==="
uv pip install -U pip setuptools wheel

echo "=== Installing ARENA requirements ==="
uv pip install --no-cache-dir -r "$REPO_DIR/requirements.txt"

# --- Clone ALL external subrepos referenced by the ARENA chapters ---
# These are cloned per-exercise by the course instructions; we bake them in so the image
# is ready offline. Each clone is shallow and idempotent.
echo "=== Cloning external course subrepos ==="
clone() {  # clone <url> <dest>
    local url="$1" dest="$2"
    if [ -d "$dest/.git" ]; then
        echo "  skip (present): $dest"
    else
        echo "  clone: $url -> $dest"
        git clone --depth 1 "$url" "$dest" || echo "  WARN: failed to clone $url (continuing)"
    fi
}

# Top-level LLM-context repo (from install.sh)
clone "https://github.com/${LLM_CONTEXT_REPO}.git" "/root/arena-llm-context"

# Chapter 1 (interp)
C1="$REPO_DIR/chapter1_transformer_interp/exercises"
clone "https://github.com/saprmarks/geometry-of-truth.git"      "$C1/geometry-of-truth"
clone "https://github.com/ApolloResearch/deception-detection.git" "$C1/deception-detection"
clone "https://github.com/decoderesearch/circuit-tracer.git"    "$C1/circuit-tracer"
clone "https://github.com/neelnanda-io/Grokking.git"            "$C1/part52_grokking_and_modular_arithmetic/Grokking"

# Chapter 2 (RL) — Pascal Pons Connect-4 solver (built by pascal_pons/build_all.sh)
clone "https://github.com/PascalPons/connect4" \
      "$REPO_DIR/chapter2_rl/exercises/part5_mcts_alphazero/pascal_pons/solver"

# Chapter 4 (alignment science)
C4="$REPO_DIR/chapter4_alignment_science/exercises"
clone "https://github.com/clarifying-EM/model-organisms-for-EM.git" "$C4/model-organisms-for-EM"
clone "https://github.com/PalisadeResearch/shutdown_avoidance.git"  "$C4/shutdown_avoidance"
clone "https://github.com/interp-reasoning/thought-anchors.git"     "$C4/thought-anchors"
clone "https://github.com/safety-research/assistant-axis.git"       "$C4/assistant-axis"
clone "https://github.com/safety-research/petri.git"                "$C4/petri"
clone "https://github.com/tim-hua-01/ai-psychosis.git"              "$C4/ai-psychosis"

# --- VS Code workspace settings (as in the repo's install.sh, pointed at the uv venv) ---
mkdir -p /root/.vscode
cat > /root/.vscode/settings.json <<EOF
{
    "python.defaultInterpreterPath": "${VENV}/bin/python",
    "python.analysis.extraPaths": [
        "${REPO_DIR}/chapter0_fundamentals/exercises",
        "${REPO_DIR}/chapter1_transformer_interp/exercises",
        "${REPO_DIR}/chapter2_rl/exercises",
        "${REPO_DIR}/chapter3_llm_evals/exercises",
        "${REPO_DIR}/chapter4_alignment_science/exercises"
    ]
}
EOF

# --- Coding agents: claude code + codex (node-free installers -> ~/.local/bin) ---
# Auth is separate (Claude Code OAuth token + ~/.claude.json come from `arena pods copy-keys`).
export PATH="/root/.local/bin:$PATH"
command -v claude >/dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash || echo "WARN: claude install failed"
if ! command -v codex >/dev/null 2>&1; then
    curl -fsSL https://chatgpt.com/codex/install.sh | sh >/dev/null 2>&1 || true
fi
if ! command -v codex >/dev/null 2>&1; then
    # Official installer has a SHA-digest bug on some hosts; fall back to the GitHub release.
    case "$(uname -m)" in aarch64|arm64) a=aarch64 ;; *) a=x86_64 ;; esac
    mkdir -p /root/.local/bin /tmp/cx
    url=$(curl -fsSL https://api.github.com/repos/openai/codex/releases/latest \
        | grep -oE "https://[^\"]*codex-${a}-unknown-linux-musl\.tar\.gz" | head -1)
    [ -n "$url" ] && { curl -fsSL "$url" | tar xz -C /tmp/cx 2>/dev/null; bin=$(find /tmp/cx -type f -name 'codex*' | head -1); [ -n "$bin" ] && install -m755 "$bin" /root/.local/bin/codex; } || echo "WARN: codex install failed"
fi
# The dotfiles .zshrc doesn't put ~/.local/bin on PATH, so symlink the agents into
# /usr/local/bin — on PATH for every shell (login, non-login, bash, zsh).
for b in claude codex; do [ -e "/root/.local/bin/$b" ] && ln -sf "/root/.local/bin/$b" "/usr/local/bin/$b"; done

# --- ffmpeg shim parity with the conda image (alias target exists at /usr/bin/ffmpeg) ---
# (No conda bin to override here; /usr/bin/ffmpeg from apt is already first on PATH.)

# --- SSH known_hosts + tmux opt-out, same as docker_setup.sh ---
mkdir -p /root/.ssh
ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null || true
chmod 600 /root/.ssh/known_hosts 2>/dev/null || true
touch /root/.no_auto_tmux

echo "=== docker_uv_setup complete: $(python --version 2>&1), torch $(python -c 'import torch; print(torch.__version__)'), jax $(python -c 'import jax; print(jax.__version__)') ==="

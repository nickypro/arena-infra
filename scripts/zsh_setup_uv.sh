#!/bin/bash
# Zsh / oh-my-zsh / powerlevel10k + ARENA MOTD setup for the uv-based GPU image.
#
# Identical shell experience to the conda GPU pods (same theme, plugins, dotfiles, figlet
# MOTD) — the ONLY change is conda -> uv arena-env activation. Self-contained: it consumes
# the dotfiles already COPY'd into the image at /root/.arena_infra (no runtime clone of
# nickypro/arena-infra, which we cannot push to).
set -euo pipefail

VENV="${VENV:-/opt/arena-env}"
INFRA_DIR="${INFRA_DIR:-/root/.arena_infra}"

echo "=== zsh_setup_uv: installing zsh + oh-my-zsh + p10k ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends zsh figlet

# Oh My Zsh (unattended; do not chsh/exec mid-build)
if [ ! -d /root/.oh-my-zsh ]; then
    RUNZSH=no CHSH=no sh -c \
        "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-/root/.oh-my-zsh/custom}"
clone_plugin() { [ -d "$2" ] || git clone --depth 1 "$1" "$2"; }
clone_plugin https://github.com/romkatv/powerlevel10k.git             "$ZSH_CUSTOM/themes/powerlevel10k"
clone_plugin https://github.com/zsh-users/zsh-autosuggestions.git     "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_plugin https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
clone_plugin https://github.com/zsh-users/zsh-history-substring-search "$ZSH_CUSTOM/plugins/zsh-history-substring-search"
clone_plugin https://github.com/zsh-users/zsh-completions             "$ZSH_CUSTOM/plugins/zsh-completions"

# Symlink p10k + vimrc verbatim from the baked-in dotfiles.
ln -sf "$INFRA_DIR/dotfiles/.vimrc"    /root/.vimrc
ln -sf "$INFRA_DIR/dotfiles/.p10k.zsh" /root/.p10k.zsh
# Use the uv-flavored .zshrc (conda block replaced with arena-env activation).
cp -f  "$INFRA_DIR/dotfiles/.zshrc.uv" /root/.zshrc

# Ensure BOTH login shells auto-activate arena-env. The .zshrc.uv already does it for zsh;
# append the same to .bashrc (idempotent) so `bash -lc` lands in arena-env too.
touch /root/.bashrc
if ! grep -qF "ARENA_ENV_ACTIVATE" /root/.bashrc; then
cat >> /root/.bashrc <<EOF

# ARENA_ENV_ACTIVATE: uv venv arena-env auto-activation (uv replaces conda on this image)
export PATH="/root/.local/bin:\$PATH"
if [ -f "${VENV}/bin/activate" ]; then
    source "${VENV}/bin/activate"
fi
EOF
fi

# MOTD (figlet ARENA banner) — same script as the conda pods.
MACHINE_NAME="${MACHINE_NAME:-root}" bash "$INFRA_DIR/scripts/motd.sh" || true

# Make zsh the default login shell.
chsh -s "$(which zsh)" root || true

echo "=== zsh_setup_uv complete ==="

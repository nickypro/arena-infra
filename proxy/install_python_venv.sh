# create a global, auto-activated virtualenv for root
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y python3-venv python3-full

VENV_DIR="$HOME/.venvs/global"
mkdir -p "$(dirname "$VENV_DIR")"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel

# auto-activate in interactive shells
BASHRC="$HOME/.bashrc"
if ! grep -q 'source ~/.venvs/global/bin/activate' "$BASHRC"; then
  cat >> "$BASHRC" <<'RC'
# Auto-activate global Python venv
if [ -z "$VIRTUAL_ENV" ] && [ -f "$HOME/.venvs/global/bin/activate" ]; then
  . "$HOME/.venvs/global/bin/activate"
fi
RC
fi

# if you use zsh, enable there too (safe if zsh isn't installed)
ZSHRC="$HOME/.zshrc"
if [ -f "$ZSHRC" ] && ! grep -q 'source ~/.venvs/global/bin/activate' "$ZSHRC"; then
  printf '\n%s\n' 'if [ -z "$VIRTUAL_ENV" ] && [ -f "$HOME/.venvs/global/bin/activate" ]; then . "$HOME/.venvs/global/bin/activate"; fi' >> "$ZSHRC"
fi

echo "Done. Open a new shell or: source ~/.bashrc"


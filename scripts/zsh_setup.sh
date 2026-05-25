#!/usr/bin/env bash
echo "Setting up environment..."
apt update
apt install -y zsh figlet
conda init zsh

# Clone dotfiles repository
cd ~
if [ ! -d "~/.arena_infra/dotfiles" ]; then
  git clone https://github.com/nickypro/arena-infra ~/.arena_infra
fi

# Install Oh My Zsh
CHSH=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Install Zsh plugins
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions

# Create symbolic links
ln -sf ~/.arena_infra/dotfiles/.zshrc ~/.zshrc
ln -sf ~/.arena_infra/dotfiles/.vimrc ~/.vimrc
ln -sf ~/.arena_infra/dotfiles/.p10k.zsh ~/.p10k.zsh

# Load machine name if present
MACHINE_NAME="root"
if [[ -r ~/.name ]]; then
  source ~/.name
fi

# Update Login MOTD
bash ~/.arena_infra/scripts/motd.sh

# make zsh default
chsh -s "$(which zsh)" root

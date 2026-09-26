# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""   # starship renders the prompt; an omz theme would be discarded
zstyle ':omz:update' mode reminder
plugins=(git docker zsh-autosuggestions zsh-syntax-highlighting)

# --- devbox: loader ---
# Everything devbox configures for zsh lives in ~/.config/devbox/zshrc, regenerated
# by setup-ubuntu.sh. Lines above this block run before it; lines below run after it.
if [ -f "$HOME/.config/devbox/zshrc" ]; then . "$HOME/.config/devbox/zshrc"; fi
# --- end devbox block ---

# User configuration
export EDITOR=vim
export PATH=$PATH:/snap/bin

myfunc() {
  echo "user function survives"
}

alias k=kubectl

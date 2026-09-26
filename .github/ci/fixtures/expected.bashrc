# ~/.bashrc: executed by bash(1) for non-login shells.
case $- in
    *i*) ;;
      *) return;;
esac
HISTSIZE=1000
HISTFILESIZE=2000
alias gs='git status'

export MY_VAR=kept

# --- devbox: loader ---
# Everything devbox configures for bash lives in ~/.config/devbox/bashrc, regenerated
# by setup-ubuntu.sh. Lines above this block run before it; lines below run after it.
if [ -f "$HOME/.config/devbox/bashrc" ]; then . "$HOME/.config/devbox/bashrc"; fi
# --- end devbox block ---

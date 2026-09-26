# ~/.bashrc: executed by bash(1) for non-login shells.
case $- in
    *i*) ;;
      *) return;;
esac
HISTSIZE=1000
HISTFILESIZE=2000
alias gs='git status'

export PATH="$HOME/.local/bin:$PATH"

source /usr/share/doc/fzf/examples/key-bindings.bash

export PATH="$HOME/.local/bin:$PATH"
eval "$(starship init bash)"

eval "$(zoxide init bash)"

# --- devbox: eza aliases ---
alias ls='eza --icons=auto'
alias ll='eza -la --icons=auto --git'
alias lt='eza --tree --level=2 --icons=auto'
# --- end devbox block ---


# devbox terminal cwd — report the cwd (OSC 7) and the tab title (OSC 0)
__devbox_term_cwd() {
  local leaf="${PWD##*/}"
  printf '\033]7;file://%s%s\033\\' "${HOSTNAME:-localhost}" "$PWD"
  printf '\033]0;%s\007' "${leaf:-/}"
}
case "${PROMPT_COMMAND:-}" in
  *__devbox_term_cwd*) ;;
  *) PROMPT_COMMAND="__devbox_term_cwd${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac

# --- devbox: bash history ---
HISTSIZE=200000
HISTFILESIZE=200000
case "${PROMPT_COMMAND:-}" in
  *'history -a'*) ;;
  *) PROMPT_COMMAND="history -a${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
# --- end devbox block ---

export MY_VAR=kept

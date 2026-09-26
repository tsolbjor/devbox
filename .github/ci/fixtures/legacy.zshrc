# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""   # starship renders the prompt; an omz theme would be discarded
zstyle ':omz:update' mode reminder
plugins=(git docker zsh-autosuggestions zsh-syntax-highlighting)


# --- devbox: zsh history ---
# Keep this block ABOVE the oh-my-zsh source line: omz's lib/history.zsh reassigns
HISTFILE="$HOME/.zsh_history"
HISTSIZE=200000     # entries held in memory
SAVEHIST=200000     # entries written to disk
setopt SHARE_HISTORY
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#7f849c'
# --- end devbox block ---

source $ZSH/oh-my-zsh.sh

# User configuration
export EDITOR=vim
export PATH="$HOME/.local/bin:$PATH"
export PATH=$PATH:/snap/bin

source /usr/share/doc/fzf/examples/key-bindings.zsh
source /usr/share/doc/fzf/examples/completion.zsh

myfunc() {
  echo "user function survives"
}

eval "$(starship init zsh)"

eval "$(zoxide init zsh)"

# devbox eza aliases
alias ls='eza --icons'
alias ll='eza -la --icons --git'
alias lt='eza --tree --level=2 --icons'


# devbox terminal cwd — report the cwd (OSC 7) and the tab title (OSC 0).
# oh-my-zsh's termsupport already does both; leave it alone when it is loaded.
__devbox_term_cwd() {
  local leaf="${PWD##*/}"
  printf '\033]7;file://%s%s\033\\' "${HOST:-localhost}" "$PWD"
  printf '\033]0;%s\007' "${leaf:-/}"
}
autoload -Uz add-zsh-hook
(( ${+functions[omz_termsupport_precmd]} )) || add-zsh-hook precmd __devbox_term_cwd

# --- devbox: zsh history keys ---
bindkey '^[[C'    autosuggest-accept
_devbox_tab_accept_or_complete() {
  zle expand-or-complete
}
zle -N _devbox_tab_accept_or_complete
bindkey '^I' _devbox_tab_accept_or_complete
# --- end devbox block ---

# --- devbox: fnm ---
if [ -x "$HOME/.local/share/fnm/fnm" ]; then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi
# --- end devbox block ---

alias k=kubectl

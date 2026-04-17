#!/usr/bin/env bash
set -euo pipefail

# =========================
# PARAMETERS (edit these)
# =========================

UPDATE_APT="${UPDATE_APT:-true}"
UPDATE_OH_MY_POSH="${UPDATE_OH_MY_POSH:-true}"
UPDATE_K9S="${UPDATE_K9S:-true}"
UPDATE_KUBECTX="${UPDATE_KUBECTX:-true}"
UPDATE_NPM_GLOBALS="${UPDATE_NPM_GLOBALS:-true}"   # runs ncu -g if ncu is available

# =========================
# IMPLEMENTATION
# =========================

CURRENT_STEP=0
TOTAL_STEPS=0

log() {
  CURRENT_STEP=$(( CURRENT_STEP + 1 ))
  printf "\n[%d/%d] %s\n" "$CURRENT_STEP" "$TOTAL_STEPS" "$*"
}

ensure_command() {
  command -v "$1" >/dev/null 2>&1
}

get_github_latest_tag() {
  curl -fsSL "https://api.github.com/repos/${1}/releases/latest" \
    | grep '"tag_name"' | cut -d'"' -f4
}

update_apt() {
  echo "→ Updating package lists"
  sudo apt-get update -y
  echo "→ Upgrading packages"
  sudo apt-get upgrade -y
  sudo apt-get autoremove -y
  echo "✓ apt packages up to date"
}

update_oh_my_posh() {
  if ! ensure_command oh-my-posh; then
    echo "✓ oh-my-posh not installed, skipping"
    return
  fi
  local before after
  before=$(oh-my-posh --version 2>/dev/null || echo "?")
  echo "→ Updating oh-my-posh (current: $before)"
  curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
  after=$(oh-my-posh --version 2>/dev/null || echo "?")
  if [[ "$before" == "$after" ]]; then
    echo "✓ oh-my-posh already at latest ($after)"
  else
    echo "✓ oh-my-posh updated: $before → $after"
  fi
}

update_k9s() {
  if ! ensure_command k9s; then
    echo "✓ k9s not installed, skipping"
    return
  fi
  local current latest arch
  current=$(k9s version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  latest=$(get_github_latest_tag "derailed/k9s")
  if [[ "$current" == "$latest" ]]; then
    echo "✓ k9s already at latest ($current)"
    return
  fi
  echo "→ Updating k9s: $current → $latest"
  arch=$(dpkg --print-architecture)
  curl -fsSL "https://github.com/derailed/k9s/releases/download/${latest}/k9s_Linux_${arch}.tar.gz" \
    | sudo tar -xz -C /usr/local/bin k9s
  echo "✓ k9s updated to $latest"
}

update_kubectx() {
  local need_ctx=false need_ns=false
  ensure_command kubectx && need_ctx=true || true
  ensure_command kubens  && need_ns=true  || true
  if [[ "$need_ctx" == "false" && "$need_ns" == "false" ]]; then
    echo "✓ kubectx/kubens not installed, skipping"
    return
  fi
  local latest dpkg_arch arch
  latest=$(get_github_latest_tag "ahmetb/kubectx")
  dpkg_arch=$(dpkg --print-architecture)
  arch=$([ "$dpkg_arch" = "amd64" ] && echo "x86_64" || echo "$dpkg_arch")
  local base="https://github.com/ahmetb/kubectx/releases/download/${latest}"
  if [[ "$need_ctx" == "true" ]]; then
    echo "→ Updating kubectx to $latest"
    curl -fsSL "${base}/kubectx_${latest}_linux_${arch}.tar.gz" \
      | sudo tar -xz -C /usr/local/bin kubectx
    echo "✓ kubectx updated to $latest"
  fi
  if [[ "$need_ns" == "true" ]]; then
    echo "→ Updating kubens to $latest"
    curl -fsSL "${base}/kubens_${latest}_linux_${arch}.tar.gz" \
      | sudo tar -xz -C /usr/local/bin kubens
    echo "✓ kubens updated to $latest"
  fi
}

update_npm_globals() {
  if ! ensure_command npm; then
    echo "✓ npm not found, skipping"
    return
  fi
  echo "→ Updating global npm packages"
  npm update -g
  echo "✓ global npm packages up to date"
}

# =========================
# RUN
# =========================

TOTAL_STEPS=1  # always: Done
[[ "$UPDATE_APT"          == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$UPDATE_OH_MY_POSH"   == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$UPDATE_K9S"          == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$UPDATE_KUBECTX"      == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$UPDATE_NPM_GLOBALS"  == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))

if [[ "$UPDATE_APT" == "true" ]]; then
  log "Updating apt packages"
  update_apt
fi

if [[ "$UPDATE_OH_MY_POSH" == "true" ]]; then
  log "Updating oh-my-posh"
  update_oh_my_posh
fi

if [[ "$UPDATE_K9S" == "true" ]]; then
  log "Updating k9s"
  update_k9s
fi

if [[ "$UPDATE_KUBECTX" == "true" ]]; then
  log "Updating kubectx/kubens"
  update_kubectx
fi

if [[ "$UPDATE_NPM_GLOBALS" == "true" ]]; then
  log "Updating global npm packages"
  update_npm_globals
fi

log "Done."

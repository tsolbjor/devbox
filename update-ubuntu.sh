#!/usr/bin/env bash
set -euo pipefail

# =========================
# PARAMETERS (edit these)
# =========================

UPDATE_APT="${UPDATE_APT:-true}"
UPDATE_OH_MY_POSH="${UPDATE_OH_MY_POSH:-true}"
UPDATE_K9S="${UPDATE_K9S:-true}"
UPDATE_KUBECTX="${UPDATE_KUBECTX:-true}"
UPDATE_NPM_GLOBALS="${UPDATE_NPM_GLOBALS:-true}"   # npm update -g if npm is available
UPDATE_PIPX="${UPDATE_PIPX:-true}"                 # pipx upgrade-all (updates uv and other pipx tools)

# =========================
# IMPLEMENTATION
# =========================

usage() {
  cat <<'EOF'
Usage: update-ubuntu.sh [options]

  --skip-apt           Skip apt update/upgrade
  --skip-oh-my-posh    Skip oh-my-posh update
  --skip-k9s           Skip k9s update
  --skip-kubectx       Skip kubectx/kubens update
  --skip-npm-globals   Skip global npm package update
  --skip-pipx          Skip pipx upgrade-all
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-apt)          UPDATE_APT=false ;;
    --skip-oh-my-posh)   UPDATE_OH_MY_POSH=false ;;
    --skip-k9s)          UPDATE_K9S=false ;;
    --skip-kubectx)      UPDATE_KUBECTX=false ;;
    --skip-npm-globals)  UPDATE_NPM_GLOBALS=false ;;
    --skip-pipx)         UPDATE_PIPX=false ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

CURRENT_STEP=0
TOTAL_STEPS=0

# Run a step; on failure, report and suggest the matching --skip flag.
# set -e is suppressed inside a function called as an `if` condition, so a
# failing command returns non-zero here instead of aborting the script.
run_step() {
  local label="$1" skip_flag="$2" fn="$3"
  log "$label"
  if ! "$fn"; then
    echo "⚠ '$label' failed. Re-run with $skip_flag to skip this step."
    exit 1
  fi
}

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
  # --allow-downgrades: pinned third-party repos (e.g. Mozilla, priority 1000)
  # can require replacing an Ubuntu snap-transition deb whose epoch makes it
  # rank as "newer"; without this, apt aborts non-zero and set -e kills the run.
  sudo apt-get upgrade -y --allow-downgrades
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

update_pipx() {
  if ! ensure_command pipx; then
    echo "✓ pipx not installed, skipping"
    return
  fi
  echo "→ Upgrading pipx-managed tools (uv, etc.)"
  pipx upgrade-all
  echo "✓ pipx tools up to date"
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
[[ "$UPDATE_PIPX"         == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))

[[ "$UPDATE_APT"         == "true" ]] && run_step "Updating apt packages"      --skip-apt          update_apt
[[ "$UPDATE_OH_MY_POSH"  == "true" ]] && run_step "Updating oh-my-posh"        --skip-oh-my-posh   update_oh_my_posh
[[ "$UPDATE_K9S"         == "true" ]] && run_step "Updating k9s"               --skip-k9s          update_k9s
[[ "$UPDATE_KUBECTX"     == "true" ]] && run_step "Updating kubectx/kubens"    --skip-kubectx      update_kubectx
[[ "$UPDATE_NPM_GLOBALS" == "true" ]] && run_step "Updating global npm packages" --skip-npm-globals update_npm_globals
[[ "$UPDATE_PIPX"        == "true" ]] && run_step "Upgrading pipx tools"          --skip-pipx         update_pipx

log "Done."

#!/usr/bin/env bash
set -euo pipefail

# =========================
# PARAMETERS (edit these)
# =========================

UPDATE_APT="${UPDATE_APT:-true}"
UPDATE_STARSHIP="${UPDATE_STARSHIP:-true}"
UPDATE_ZOXIDE="${UPDATE_ZOXIDE:-true}"
UPDATE_DELTA="${UPDATE_DELTA:-true}"
UPDATE_LAZYGIT="${UPDATE_LAZYGIT:-true}"
UPDATE_STERN="${UPDATE_STERN:-true}"
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
  --skip-starship      Skip starship update
  --skip-zoxide        Skip zoxide update
  --skip-delta         Skip git-delta update
  --skip-lazygit       Skip lazygit update
  --skip-stern         Skip stern update
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
    --skip-starship)     UPDATE_STARSHIP=false ;;
    --skip-zoxide)       UPDATE_ZOXIDE=false ;;
    --skip-delta)        UPDATE_DELTA=false ;;
    --skip-lazygit)      UPDATE_LAZYGIT=false ;;
    --skip-stern)        UPDATE_STERN=false ;;
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

update_starship() {
  if ! ensure_command starship; then
    echo "✓ starship not installed, skipping"
    return
  fi
  local before after
  before=$(starship --version 2>/dev/null | head -1 || echo "?")
  echo "→ Updating starship (current: $before)"
  curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin"
  after=$(starship --version 2>/dev/null | head -1 || echo "?")
  if [[ "$before" == "$after" ]]; then
    echo "✓ starship already at latest ($after)"
  else
    echo "✓ starship updated: $before → $after"
  fi
}

update_zoxide() {
  if ! ensure_command zoxide; then
    echo "✓ zoxide not installed, skipping"
    return
  fi
  local before after
  before=$(zoxide --version 2>/dev/null || echo "?")
  echo "→ Updating zoxide (current: $before)"
  curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh \
    | sh -s -- --bin-dir "$HOME/.local/bin"
  after=$(zoxide --version 2>/dev/null || echo "?")
  if [[ "$before" == "$after" ]]; then
    echo "✓ zoxide already at latest ($after)"
  else
    echo "✓ zoxide updated: $before → $after"
  fi
}

update_delta() {
  if ! ensure_command delta; then
    echo "✓ delta not installed, skipping"
    return
  fi
  local current latest arch
  current=$(delta --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  latest=$(get_github_latest_tag "dandavison/delta")   # no leading 'v'
  if [[ "$current" == "$latest" ]]; then
    echo "✓ delta already at latest ($current)"
    return
  fi
  echo "→ Updating delta: $current → $latest"
  arch=$([ "$(dpkg --print-architecture)" = "amd64" ] && echo "x86_64" || echo "aarch64")
  curl -fsSL "https://github.com/dandavison/delta/releases/download/${latest}/delta-${latest}-${arch}-unknown-linux-gnu.tar.gz" \
    | sudo tar -xz --strip-components=1 -C /usr/local/bin "delta-${latest}-${arch}-unknown-linux-gnu/delta"
  echo "✓ delta updated to $latest"
}

update_lazygit() {
  if ! ensure_command lazygit; then
    echo "✓ lazygit not installed, skipping"
    return
  fi
  local current latest num arch
  current=$(lazygit --version 2>/dev/null | grep -oE 'version=[0-9]+\.[0-9]+\.[0-9]+' | cut -d= -f2 | head -1 || echo "unknown")
  latest=$(get_github_latest_tag "jesseduffield/lazygit")   # vX.Y.Z
  num="${latest#v}"
  if [[ "$current" == "$num" ]]; then
    echo "✓ lazygit already at latest ($current)"
    return
  fi
  echo "→ Updating lazygit: $current → $num"
  arch=$([ "$(dpkg --print-architecture)" = "amd64" ] && echo "x86_64" || echo "arm64")
  curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/${latest}/lazygit_${num}_Linux_${arch}.tar.gz" \
    | sudo tar -xz -C /usr/local/bin lazygit
  echo "✓ lazygit updated to $num"
}

update_stern() {
  if ! ensure_command stern; then
    echo "✓ stern not installed, skipping"
    return
  fi
  local current latest num dpkg_arch
  current=$(stern --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  latest=$(get_github_latest_tag "stern/stern")   # vX.Y.Z
  num="${latest#v}"
  if [[ "$current" == "$num" ]]; then
    echo "✓ stern already at latest ($current)"
    return
  fi
  echo "→ Updating stern: $current → $num"
  dpkg_arch=$(dpkg --print-architecture)
  curl -fsSL "https://github.com/stern/stern/releases/download/${latest}/stern_${num}_linux_${dpkg_arch}.tar.gz" \
    | sudo tar -xz -C /usr/local/bin stern
  echo "✓ stern updated to $num"
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
[[ "$UPDATE_STARSHIP"     == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$UPDATE_ZOXIDE"       == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$UPDATE_DELTA"        == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$UPDATE_LAZYGIT"      == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$UPDATE_STERN"        == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$UPDATE_K9S"          == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$UPDATE_KUBECTX"      == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$UPDATE_NPM_GLOBALS"  == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$UPDATE_PIPX"         == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))

[[ "$UPDATE_APT"         == "true" ]] && run_step "Updating apt packages"      --skip-apt          update_apt
[[ "$UPDATE_STARSHIP"    == "true" ]] && run_step "Updating starship"          --skip-starship     update_starship
[[ "$UPDATE_ZOXIDE"      == "true" ]] && run_step "Updating zoxide"            --skip-zoxide       update_zoxide
[[ "$UPDATE_DELTA"       == "true" ]] && run_step "Updating git-delta"         --skip-delta        update_delta
[[ "$UPDATE_LAZYGIT"     == "true" ]] && run_step "Updating lazygit"           --skip-lazygit      update_lazygit
[[ "$UPDATE_STERN"       == "true" ]] && run_step "Updating stern"             --skip-stern        update_stern
[[ "$UPDATE_K9S"         == "true" ]] && run_step "Updating k9s"               --skip-k9s          update_k9s
[[ "$UPDATE_KUBECTX"     == "true" ]] && run_step "Updating kubectx/kubens"    --skip-kubectx      update_kubectx
[[ "$UPDATE_NPM_GLOBALS" == "true" ]] && run_step "Updating global npm packages" --skip-npm-globals update_npm_globals
[[ "$UPDATE_PIPX"        == "true" ]] && run_step "Upgrading pipx tools"          --skip-pipx         update_pipx

log "Done."

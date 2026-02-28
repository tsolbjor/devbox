#!/usr/bin/env bash
set -euo pipefail

# =========================
# PARAMETERS (edit these)
# =========================

GIT_NAME="${GIT_NAME:-Your Name}"
GIT_EMAIL="${GIT_EMAIL:-your.email@example.com}"

# Where you keep repos inside WSL
CODE_DIR="${CODE_DIR:-$HOME/code}"

# Base packages installed in WSL (keep this minimal if you rely on devcontainers)
APT_PACKAGES=(
  ca-certificates
  curl
  unzip
  git
  gnupg
  lsb-release
  build-essential
  jq
  ripgrep
  fd-find
)

# Optional installs
INSTALL_GITHUB_CLI="${INSTALL_GITHUB_CLI:-true}"   # installs `gh` from Ubuntu repo if available
SET_GIT_DEFAULTS="${SET_GIT_DEFAULTS:-true}"
ENSURE_SSH_KEY="${ENSURE_SSH_KEY:-true}"

# Git defaults
GIT_DEFAULT_BRANCH="${GIT_DEFAULT_BRANCH:-main}"
GIT_AUTOCRLF="${GIT_AUTOCRLF:-input}"             # best default for WSL
SSH_KEY_TYPE="${SSH_KEY_TYPE:-ed25519}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"

# =========================
# IMPLEMENTATION
# =========================

log() { printf "\n%s\n" "$*"; }

is_pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

ensure_pkg() {
  local pkg="$1"
  if is_pkg_installed "$pkg"; then
    echo "✓ apt package already installed: $pkg"
  else
    echo "→ Installing apt package: $pkg"
    sudo apt-get install -y "$pkg"
  fi
}

ensure_dir() {
  local d="$1"
  if [[ -d "$d" ]]; then
    echo "✓ Directory exists: $d"
  else
    echo "→ Creating directory: $d"
    mkdir -p "$d"
  fi
}

ensure_git_config() {
  local key="$1"
  local val="$2"
  local current
  current="$(git config --global --get "$key" || true)"
  if [[ "$current" == "$val" ]]; then
    echo "✓ git config $key already set"
  else
    echo "→ Setting git config $key = $val"
    git config --global "$key" "$val"
  fi
}

ensure_ssh_key() {
  if [[ -f "$SSH_KEY_PATH" ]]; then
    echo "✓ SSH key exists: $SSH_KEY_PATH"
    return
  fi
  echo "→ Creating SSH key: $SSH_KEY_PATH"
  mkdir -p "$(dirname "$SSH_KEY_PATH")"
  ssh-keygen -t "$SSH_KEY_TYPE" -f "$SSH_KEY_PATH" -N "" -C "$GIT_EMAIL"
  echo "✓ Created SSH key. Public key:"
  cat "${SSH_KEY_PATH}.pub"
}

ensure_command() {
  command -v "$1" >/dev/null 2>&1
}

# =========================
# RUN
# =========================

log "Updating apt metadata"
sudo apt-get update -y

log "Installing base packages"
for p in "${APT_PACKAGES[@]}"; do
  ensure_pkg "$p"
done

# fd package is called fd-find on Ubuntu; provide `fd` alias symlink idempotently
if ensure_command fdfind && ! ensure_command fd; then
  if [[ -L "$HOME/.local/bin/fd" || -f "$HOME/.local/bin/fd" ]]; then
    echo "✓ fd shim already exists"
  else
    echo "→ Creating fd shim at ~/.local/bin/fd"
    mkdir -p "$HOME/.local/bin"
    ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc" 2>/dev/null || true
  fi
fi

log "Ensuring code directory"
ensure_dir "$CODE_DIR"

if [[ "$SET_GIT_DEFAULTS" == "true" ]]; then
  log "Configuring Git (global)"
  ensure_git_config "user.name" "$GIT_NAME"
  ensure_git_config "user.email" "$GIT_EMAIL"
  ensure_git_config "init.defaultBranch" "$GIT_DEFAULT_BRANCH"
  ensure_git_config "core.autocrlf" "$GIT_AUTOCRLF"
fi

if [[ "$INSTALL_GITHUB_CLI" == "true" ]]; then
  log "Installing GitHub CLI (gh) if available"
  if ensure_command gh; then
    echo "✓ gh already installed"
  else
    # Ubuntu repo version is usually good enough; keep it simple and idempotent
    if apt-cache show gh >/dev/null 2>&1; then
      ensure_pkg "gh"
    else
      echo "⚠ gh not found in apt repo for this Ubuntu. Skipping."
    fi
  fi
fi

if [[ "$ENSURE_SSH_KEY" == "true" ]]; then
  log "Ensuring SSH key"
  ensure_ssh_key
fi

log "Done."
echo "Next steps:"
echo " - Clone repos into: $CODE_DIR"
echo " - Open from WSL: cd <repo> && code ."
echo " - Then: 'Reopen in Container' when .devcontainer/ exists"
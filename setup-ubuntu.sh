#!/usr/bin/env bash
set -euo pipefail

# =========================
# PARAMETERS (edit these)
# =========================

GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"

# Where you keep repos inside WSL
CODE_DIR="${CODE_DIR:-$HOME/code}"

# Base packages installed in WSL (keep this minimal if you rely on devcontainers)
APT_PACKAGES=(
  ca-certificates
  curl
  wget
  unzip
  zip
  git
  gnupg
  lsb-release
  build-essential
  jq
  ripgrep
  fd-find
  fzf
  zsh
)

# Optional installs
INSTALL_GITHUB_CLI="${INSTALL_GITHUB_CLI:-true}"
INSTALL_KUBECTL="${INSTALL_KUBECTL:-true}"
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.32}"   # Kubernetes minor version for apt repo
INSTALL_HELM="${INSTALL_HELM:-true}"
INSTALL_K9S="${INSTALL_K9S:-true}"
INSTALL_KUBECTX="${INSTALL_KUBECTX:-true}"
INSTALL_OH_MY_POSH="${INSTALL_OH_MY_POSH:-true}"
OH_MY_POSH_THEME="${OH_MY_POSH_THEME:-jandedobbeleer}"   # name from https://ohmyposh.dev/docs/themes
CONFIGURE_WSL_CONF="${CONFIGURE_WSL_CONF:-true}"   # set false on native Linux (not WSL)
WSL_ENABLE_SYSTEMD="${WSL_ENABLE_SYSTEMD:-true}"   # requires Windows 11 22H2+ / WSL 2.0
SET_ZSH_DEFAULT="${SET_ZSH_DEFAULT:-true}"
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

CURRENT_STEP=0
TOTAL_STEPS=0

log() {
  CURRENT_STEP=$(( CURRENT_STEP + 1 ))
  printf "\n[%d/%d] %s\n" "$CURRENT_STEP" "$TOTAL_STEPS" "$*"
}

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

ensure_kubectl() {
  if ensure_command kubectl; then
    echo "✓ kubectl already installed"
    return
  fi
  echo "→ Installing kubectl (${KUBECTL_VERSION})"
  if [[ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]]; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBECTL_VERSION}/deb/Release.key" \
      | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  fi
  if [[ ! -f /etc/apt/sources.list.d/kubernetes.list ]]; then
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBECTL_VERSION}/deb/ /" \
      | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
    sudo apt-get update -y
  fi
  sudo apt-get install -y kubectl
  echo "✓ kubectl installed"
}

ensure_helm() {
  if ensure_command helm; then
    echo "✓ helm already installed"
    return
  fi
  echo "→ Installing helm"
  if [[ ! -f /usr/share/keyrings/helm.gpg ]]; then
    curl -fsSL https://baltocdn.com/helm/signing.asc \
      | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
  fi
  if [[ ! -f /etc/apt/sources.list.d/helm-stable-debian.list ]]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" \
      | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list > /dev/null
    sudo apt-get update -y
  fi
  sudo apt-get install -y helm
  echo "✓ helm installed"
}

ensure_k9s() {
  if ensure_command k9s; then
    echo "✓ k9s already installed"
    return
  fi
  echo "→ Installing k9s (latest)"
  local version arch
  version=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
  arch=$(dpkg --print-architecture)
  curl -fsSL "https://github.com/derailed/k9s/releases/download/${version}/k9s_Linux_${arch}.tar.gz" \
    | sudo tar -xz -C /usr/local/bin k9s
  echo "✓ k9s ${version} installed"
}

ensure_fzf_shell_integration() {
  for pair in ".bashrc:bash" ".zshrc:zsh"; do
    local rc="$HOME/${pair%%:*}"
    local shell="${pair##*:}"
    [[ -f "$rc" ]] || continue
    if grep -q 'fzf' "$rc"; then
      echo "✓ fzf already in $(basename "$rc")"
      continue
    fi
    local binding="/usr/share/doc/fzf/examples/key-bindings.${shell}"
    local completion="/usr/share/doc/fzf/examples/completion.${shell}"
    [[ -f "$binding" ]] || continue
    echo "→ Adding fzf key bindings to $(basename "$rc")"
    printf '\nsource %s\n' "$binding" >> "$rc"
    [[ -f "$completion" ]] && printf 'source %s\n' "$completion" >> "$rc"
  done
}

ensure_wsl_conf() {
  local conf="/etc/wsl.conf"
  local boot_line=""
  [[ "$WSL_ENABLE_SYSTEMD" == "true" ]] && boot_line=$'\n[boot]\nsystemd = true'
  local desired="[automount]
options = metadata${boot_line}
"
  local current=""
  [[ -f "$conf" ]] && current=$(cat "$conf")
  if [[ "$current" == "$desired" ]]; then
    echo "✓ /etc/wsl.conf already matches desired settings"
    return
  fi
  echo "→ Writing /etc/wsl.conf"
  printf '%s' "$desired" | sudo tee "$conf" > /dev/null
  echo "✓ /etc/wsl.conf updated — run 'wsl --shutdown' from Windows then reopen WSL to apply."
}

ensure_kubectx() {
  local need_ctx=true need_ns=true
  ensure_command kubectx && need_ctx=false
  ensure_command kubens  && need_ns=false
  if [[ "$need_ctx" == "false" && "$need_ns" == "false" ]]; then
    echo "✓ kubectx and kubens already installed"
    return
  fi
  echo "→ Installing kubectx and kubens (latest)"
  local version dpkg_arch arch
  version=$(curl -fsSL https://api.github.com/repos/ahmetb/kubectx/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
  dpkg_arch=$(dpkg --print-architecture)
  arch=$([ "$dpkg_arch" = "amd64" ] && echo "x86_64" || echo "$dpkg_arch")
  local base="https://github.com/ahmetb/kubectx/releases/download/${version}"
  if [[ "$need_ctx" == "true" ]]; then
    curl -fsSL "${base}/kubectx_${version}_linux_${arch}.tar.gz" \
      | sudo tar -xz -C /usr/local/bin kubectx
  fi
  if [[ "$need_ns" == "true" ]]; then
    curl -fsSL "${base}/kubens_${version}_linux_${arch}.tar.gz" \
      | sudo tar -xz -C /usr/local/bin kubens
  fi
  echo "✓ kubectx/kubens ${version} installed"
}

ensure_oh_my_posh() {
  # Install binary
  if ensure_command oh-my-posh; then
    echo "✓ oh-my-posh already installed"
  else
    echo "→ Installing oh-my-posh"
    curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
    # Ensure ~/.local/bin is on PATH in all present shell rc files (idempotent)
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
      if [[ -f "$rc" ]] && ! grep -q '\.local/bin' "$rc"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
        echo "→ Added ~/.local/bin to PATH in $(basename "$rc")"
      fi
    done
  fi

  # Download theme
  local config_dir="$HOME/.config/oh-my-posh"
  local theme_file="$config_dir/theme.omp.json"
  if [[ -f "$theme_file" ]]; then
    echo "✓ oh-my-posh theme already present: $theme_file"
  else
    echo "→ Downloading oh-my-posh theme: $OH_MY_POSH_THEME"
    mkdir -p "$config_dir"
    curl -fsSL "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/${OH_MY_POSH_THEME}.omp.json" \
      -o "$theme_file"
    echo "✓ Theme saved to $theme_file"
  fi

  # Wire init into shell rc files (idempotent)
  if [[ -f "$HOME/.bashrc" ]] && ! grep -q 'oh-my-posh' "$HOME/.bashrc"; then
    echo "→ Adding oh-my-posh init to .bashrc"
    printf '\neval "$(oh-my-posh init bash --config ~/.config/oh-my-posh/theme.omp.json)"\n' >> "$HOME/.bashrc"
  elif [[ -f "$HOME/.bashrc" ]]; then
    echo "✓ oh-my-posh already in .bashrc"
  fi
  if [[ -f "$HOME/.zshrc" ]] && ! grep -q 'oh-my-posh' "$HOME/.zshrc"; then
    echo "→ Adding oh-my-posh init to .zshrc"
    printf '\neval "$(oh-my-posh init zsh --config ~/.config/oh-my-posh/theme.omp.json)"\n' >> "$HOME/.zshrc"
  elif [[ -f "$HOME/.zshrc" ]]; then
    echo "✓ oh-my-posh already in .zshrc"
  fi
}

# =========================
# RUN
# =========================

# Validate required parameters
if [[ "$SET_GIT_DEFAULTS" == "true" ]]; then
  if [[ -z "$GIT_NAME" ]]; then
    echo "ERROR: GIT_NAME is not set. Please set it as an environment variable." >&2
    echo "Example: export GIT_NAME='Your Name'" >&2
    exit 1
  fi
  if [[ -z "$GIT_EMAIL" ]]; then
    echo "ERROR: GIT_EMAIL is not set. Please set it as an environment variable." >&2
    echo "Example: export GIT_EMAIL='your.email@example.com'" >&2
    exit 1
  fi
fi

# Compute total step count for progress display
TOTAL_STEPS=7  # apt update, base packages, zsh, fd shim, fzf, code dir, Done
[[ "$CONFIGURE_WSL_CONF" == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$SET_GIT_DEFAULTS"   == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_GITHUB_CLI" == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_KUBECTL"    == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_HELM"       == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_K9S"        == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_KUBECTX"    == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_OH_MY_POSH" == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$ENSURE_SSH_KEY"     == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))

log "Updating apt metadata"
sudo apt-get update -y

log "Installing base packages"
for p in "${APT_PACKAGES[@]}"; do
  ensure_pkg "$p"
done

if [[ "$CONFIGURE_WSL_CONF" == "true" ]]; then
  log "Configuring /etc/wsl.conf"
  ensure_wsl_conf
fi

log "Setting up zsh"
# Ensure .zshrc exists so later sections (fd PATH, fzf, oh-my-posh) can write to it
if is_pkg_installed zsh; then
  if [[ ! -f "$HOME/.zshrc" ]]; then
    echo "→ Creating minimal ~/.zshrc"
    touch "$HOME/.zshrc"
  else
    echo "✓ ~/.zshrc exists"
  fi
  if [[ "$SET_ZSH_DEFAULT" == "true" ]]; then
    zsh_path="$(command -v zsh)"
    current_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$current_shell" == "$zsh_path" ]]; then
      echo "✓ zsh is already the default shell"
    else
      echo "→ Setting zsh as default shell"
      sudo chsh -s "$zsh_path" "$USER"
      echo "✓ Default shell set to zsh (takes effect on next login)"
    fi
  fi
fi

log "Setting up fd shim"
# fd package is called fd-find on Ubuntu; provide `fd` alias symlink idempotently
if ensure_command fdfind && ! ensure_command fd; then
  if [[ -L "$HOME/.local/bin/fd" || -f "$HOME/.local/bin/fd" ]]; then
    echo "✓ fd shim already exists"
  else
    echo "→ Creating fd shim at ~/.local/bin/fd"
    mkdir -p "$HOME/.local/bin"
    ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
  # Ensure ~/.local/bin is on PATH in all present shell rc files (idempotent)
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc" ]] && ! grep -q '\.local/bin' "$rc"; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
      echo "→ Added ~/.local/bin to PATH in $(basename "$rc")"
    fi
  done
fi

log "Configuring fzf shell integration"
ensure_fzf_shell_integration

log "Ensuring code directory"
ensure_dir "$CODE_DIR"

if [[ "$SET_GIT_DEFAULTS" == "true" ]]; then
  log "Configuring Git (global)"
  ensure_git_config "user.name" "$GIT_NAME"
  ensure_git_config "user.email" "$GIT_EMAIL"
  ensure_git_config "init.defaultBranch" "$GIT_DEFAULT_BRANCH"
  ensure_git_config "core.autocrlf" "$GIT_AUTOCRLF"
  ensure_git_config "pull.rebase" "false"
  ensure_git_config "push.autoSetupRemote" "true"
fi

if [[ "$INSTALL_GITHUB_CLI" == "true" ]]; then
  log "Installing GitHub CLI (gh)"
  if ensure_command gh; then
    echo "✓ gh already installed"
  else
    echo "→ Adding GitHub CLI official apt repo"
    if [[ ! -f /usr/share/keyrings/githubcli-archive-keyring.gpg ]]; then
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
      sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    fi
    if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      sudo apt-get update -y
    fi
    sudo apt-get install -y gh
  fi
fi

if [[ "$INSTALL_KUBECTL" == "true" ]]; then
  log "Installing kubectl"
  ensure_kubectl
fi

if [[ "$INSTALL_HELM" == "true" ]]; then
  log "Installing helm"
  ensure_helm
fi

if [[ "$INSTALL_K9S" == "true" ]]; then
  log "Installing k9s"
  ensure_k9s
fi

if [[ "$INSTALL_KUBECTX" == "true" ]]; then
  log "Installing kubectx and kubens"
  ensure_kubectx
fi

if [[ "$INSTALL_OH_MY_POSH" == "true" ]]; then
  log "Installing oh-my-posh"
  ensure_oh_my_posh
fi

if [[ "$ENSURE_SSH_KEY" == "true" ]]; then
  log "Ensuring SSH key"
  ensure_ssh_key
fi

log "Done."
echo "Next steps:"
if [[ -f "${SSH_KEY_PATH}.pub" ]]; then
  echo " 1. Add your SSH public key to GitHub → https://github.com/settings/keys"
  echo "    $(cat "${SSH_KEY_PATH}.pub")"
else
  echo " 1. Generate an SSH key and add it to GitHub → https://github.com/settings/keys"
fi
echo " 2. Authenticate GitHub CLI: gh auth login"
echo " 3. Clone repos into: $CODE_DIR"
echo " 4. Open a repo: cd <repo> && code ."
echo " 5. Select 'Reopen in Container' in VS Code when a .devcontainer/ exists"
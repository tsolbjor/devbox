#!/usr/bin/env bash
set -euo pipefail

# =========================
# PARAMETERS (edit these)
# =========================

GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"

# When GIT_NAME/GIT_EMAIL are empty and we're inside WSL, try to derive them from the
# logged-in Windows (Entra) user via interop. Explicitly-set env vars always win.
AUTO_DETECT_GIT_IDENTITY="${AUTO_DETECT_GIT_IDENTITY:-true}"

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
INSTALL_NODE="${INSTALL_NODE:-true}"
NODE_MAJOR_VERSION="${NODE_MAJOR_VERSION:-22}"   # LTS; https://nodejs.org/en/about/previous-releases
CONFIGURE_WSL_CONF="${CONFIGURE_WSL_CONF:-true}"   # set false on native Linux (not WSL)
WSL_ENABLE_SYSTEMD="${WSL_ENABLE_SYSTEMD:-true}"   # requires Windows 11 22H2+ / WSL 2.0
SET_ZSH_DEFAULT="${SET_ZSH_DEFAULT:-true}"
SET_GIT_DEFAULTS="${SET_GIT_DEFAULTS:-true}"
ENSURE_SSH_KEY="${ENSURE_SSH_KEY:-true}"
INSTALL_DOTNET="${INSTALL_DOTNET:-true}"
DOTNET_SDK_VERSION="${DOTNET_SDK_VERSION:-8.0}"   # e.g. 8.0 (LTS) or 10.0; https://dotnet.microsoft.com/download
INSTALL_PYTHON="${INSTALL_PYTHON:-true}"          # python3 venv/pip + pipx + uv
DOCKER_CHECK="${DOCKER_CHECK:-true}"              # verify Rancher Desktop's docker is wired into WSL
GIT_SIGN_COMMITS="${GIT_SIGN_COMMITS:-true}"      # SSH-sign commits/tags with the generated key

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

win_strip() {
  # Windows tools emit trailing CR (+ whitespace); strip to a clean single line.
  tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | head -n1
}

detect_windows_git_identity() {
  [[ "$AUTO_DETECT_GIT_IDENTITY" == "true" ]] || return 0
  # Only meaningful on WSL, where Windows interop binaries are on PATH.
  grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null || return 0

  if [[ -z "$GIT_EMAIL" ]] && ensure_command whoami.exe; then
    local upn
    upn="$(whoami.exe /upn 2>/dev/null | win_strip)"
    if [[ "$upn" == *@*.* ]]; then
      GIT_EMAIL="$upn"
      echo "→ Detected Git email from Windows UPN: $GIT_EMAIL"
    fi
  fi

  if [[ -z "$GIT_NAME" ]] && ensure_command powershell.exe; then
    local disp
    disp="$(powershell.exe -NoProfile -NonInteractive -Command \
      "(Get-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Authentication\\LogonUI' -Name LastLoggedOnDisplayName -ErrorAction SilentlyContinue).LastLoggedOnDisplayName" \
      2>/dev/null | win_strip)"
    if [[ -n "$disp" ]]; then
      GIT_NAME="$disp"
      echo "→ Detected Git name from Windows logon display name: $GIT_NAME"
    fi
  fi

  # Fallback: derive a name from the UPN local-part (e.g. thomas.solbjor -> Thomas Solbjor).
  if [[ -z "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
    GIT_NAME="$(echo "${GIT_EMAIL%%@*}" | tr '._-' '   ' \
      | sed -e 's/\b\(.\)/\u\1/g' -e 's/[[:space:]]\+/ /g' -e 's/^ //;s/ $//')"
    echo "→ Derived Git name from email local-part: $GIT_NAME"
  fi
}

ensure_git_safe_directory() {
  # Repos on /mnt/c or accessed across the \\wsl$ boundary can trip Git's
  # "dubious ownership" guard. Mark CODE_DIR trusted (idempotent — no duplicate entry).
  local dir="$1"
  if git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$dir"; then
    echo "✓ git safe.directory already set: $dir"
  else
    echo "→ Marking git safe.directory: $dir"
    git config --global --add safe.directory "$dir"
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
  ensure_command fzf || { echo "⚠ fzf not installed; skipping shell integration"; return; }

  # fzf 0.48+ generates integration inline (`fzf --bash` / `--zsh`), which is
  # version-proof. Older packaged fzf (e.g. Ubuntu 24.04 ships 0.44) has no such
  # flag, so fall back to sourcing the packaged example scripts, whose location
  # has moved across Debian/Ubuntu releases — hence multiple candidate paths.
  local supports_flag=false
  fzf --bash >/dev/null 2>&1 && supports_flag=true

  for pair in ".bashrc:bash" ".zshrc:zsh"; do
    local rc="$HOME/${pair%%:*}"
    local shell="${pair##*:}"
    [[ -f "$rc" ]] || continue
    if grep -q 'fzf' "$rc"; then
      echo "✓ fzf already in $(basename "$rc")"
      continue
    fi

    if [[ "$supports_flag" == "true" ]]; then
      echo "→ Adding fzf integration to $(basename "$rc") (fzf --${shell})"
      printf '\neval "$(fzf --%s)"\n' "$shell" >> "$rc"
      continue
    fi

    local binding="" completion=""
    for dir in /usr/share/doc/fzf/examples /usr/share/fzf /usr/share/fzf/shell; do
      if [[ -f "$dir/key-bindings.${shell}" ]]; then
        binding="$dir/key-bindings.${shell}"
        [[ -f "$dir/completion.${shell}" ]] && completion="$dir/completion.${shell}"
        break
      fi
    done
    if [[ -z "$binding" ]]; then
      echo "⚠ fzf too old for 'fzf --${shell}' and no example scripts found; skipping $(basename "$rc")"
      continue
    fi
    echo "→ Adding fzf key bindings to $(basename "$rc")"
    printf '\nsource %s\n' "$binding" >> "$rc"
    [[ -n "$completion" ]] && printf 'source %s\n' "$completion" >> "$rc"
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
  echo "  Note: network settings like mirrored mode and localhostForwarding belong in %UserProfile%/.wslconfig on Windows, not /etc/wsl.conf."
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

ensure_node() {
  if ensure_command node; then
    echo "✓ node already installed ($(node --version))"
  else
    echo "→ Installing Node.js ${NODE_MAJOR_VERSION}.x (NodeSource)"
    if [[ ! -f /etc/apt/keyrings/nodesource.gpg ]]; then
      sudo mkdir -p /etc/apt/keyrings
      curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    fi
    if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
      echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR_VERSION}.x nodistro main" \
        | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
      sudo apt-get update -y
    fi
    sudo apt-get install -y nodejs
    echo "✓ node installed ($(node --version))"
  fi

  if ensure_command ncu; then
    echo "✓ ncu already installed"
  else
    echo "→ Installing ncu (npm-check-updates)"
    sudo npm install -g npm-check-updates
    echo "✓ ncu installed"
  fi
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

ensure_dotnet() {
  if ensure_command dotnet; then
    echo "✓ dotnet already installed ($(dotnet --version 2>/dev/null))"
    return
  fi
  local pkg="dotnet-sdk-${DOTNET_SDK_VERSION}"
  echo "→ Installing .NET SDK ${DOTNET_SDK_VERSION}"
  # Prefer the distro feed (Ubuntu 24.04+ ships dotnet); fall back to Microsoft's
  # feed for versions/releases Canonical doesn't package.
  if ! apt-cache show "$pkg" >/dev/null 2>&1; then
    echo "→ Adding Microsoft package feed"
    local ver_id
    ver_id="$(. /etc/os-release && echo "$VERSION_ID")"
    local deb="/tmp/packages-microsoft-prod.deb"
    curl -fsSL "https://packages.microsoft.com/config/ubuntu/${ver_id}/packages-microsoft-prod.deb" -o "$deb"
    sudo dpkg -i "$deb"
    rm -f "$deb"
    sudo apt-get update -y
  fi
  sudo apt-get install -y "$pkg"
  echo "✓ .NET SDK installed ($(dotnet --version 2>/dev/null))"
}

ensure_python() {
  for p in python3 python3-venv python3-pip pipx; do
    ensure_pkg "$p"
  done
  # Put pipx-installed tools on PATH (idempotent; writes to rc files if needed).
  pipx ensurepath >/dev/null 2>&1 || true
  if pipx list 2>/dev/null | grep -q '\buv\b'; then
    echo "✓ uv already installed"
  else
    echo "→ Installing uv (via pipx)"
    pipx install uv
  fi
}

docker_check() {
  if ensure_command docker && docker version >/dev/null 2>&1; then
    echo "✓ docker reachable from WSL ($(docker version --format '{{.Client.Version}}' 2>/dev/null))"
  elif ensure_command docker; then
    echo "⚠ docker CLI present but daemon not reachable. Start Rancher Desktop (moby engine)."
  else
    echo "⚠ docker not found in WSL."
    echo "  In Rancher Desktop: Preferences → WSL → Integrations → enable '$(. /etc/os-release && echo "$NAME")' (this distro)."
  fi
}

ensure_git_signing() {
  # SSH-sign commits/tags with the key we generate. GitHub verifies these once the
  # SAME public key is added as a *Signing key* (in addition to an Authentication key).
  [[ -f "${SSH_KEY_PATH}.pub" ]] || { echo "⚠ No SSH key at ${SSH_KEY_PATH}.pub; skipping commit signing."; return; }
  ensure_git_config "gpg.format" "ssh"
  ensure_git_config "user.signingkey" "${SSH_KEY_PATH}.pub"
  ensure_git_config "commit.gpgsign" "true"
  ensure_git_config "tag.gpgsign" "true"
}

# =========================
# RUN
# =========================

# Validate required parameters
if [[ "$SET_GIT_DEFAULTS" == "true" ]]; then
  detect_windows_git_identity
  if [[ -z "$GIT_NAME" ]]; then
    echo "ERROR: GIT_NAME is not set and could not be detected from Windows." >&2
    echo "Set it explicitly: export GIT_NAME='Your Name'" >&2
    exit 1
  fi
  if [[ -z "$GIT_EMAIL" ]]; then
    echo "ERROR: GIT_EMAIL is not set and could not be detected from Windows." >&2
    echo "Set it explicitly: export GIT_EMAIL='your.email@example.com'" >&2
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
[[ "$INSTALL_NODE"       == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_DOTNET"     == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_PYTHON"     == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$DOCKER_CHECK"       == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
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
  ensure_git_safe_directory "$CODE_DIR"
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

if [[ "$INSTALL_NODE" == "true" ]]; then
  log "Installing Node.js and ncu"
  ensure_node
fi

if [[ "$INSTALL_DOTNET" == "true" ]]; then
  log "Installing .NET SDK"
  ensure_dotnet
fi

if [[ "$INSTALL_PYTHON" == "true" ]]; then
  log "Installing Python (venv/pip/pipx/uv)"
  ensure_python
fi

if [[ "$DOCKER_CHECK" == "true" ]]; then
  log "Checking docker (Rancher Desktop WSL integration)"
  docker_check
fi

if [[ "$ENSURE_SSH_KEY" == "true" ]]; then
  log "Ensuring SSH key"
  ensure_ssh_key
  if [[ "$SET_GIT_DEFAULTS" == "true" && "$GIT_SIGN_COMMITS" == "true" ]]; then
    ensure_git_signing
  fi
fi

log "Done."
echo "Next steps:"
if [[ -f "${SSH_KEY_PATH}.pub" ]]; then
  echo " 1. Add your SSH public key to GitHub → https://github.com/settings/keys"
  echo "    $(cat "${SSH_KEY_PATH}.pub")"
  if [[ "$SET_GIT_DEFAULTS" == "true" && "$GIT_SIGN_COMMITS" == "true" ]]; then
    echo "    Add it TWICE: once as an 'Authentication key' and once as a 'Signing key'"
    echo "    (commits are SSH-signed; signing key is required for the Verified badge)."
  fi
else
  echo " 1. Generate an SSH key and add it to GitHub → https://github.com/settings/keys"
fi
echo " 2. Authenticate GitHub CLI: gh auth login"
echo " 3. Clone repos into: $CODE_DIR"
echo " 4. Open a repo: cd <repo> && code ."
echo " 5. Select 'Reopen in Container' in VS Code when a .devcontainer/ exists"

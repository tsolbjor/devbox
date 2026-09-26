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
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.37}"   # Kubernetes minor version for apt repo. Keep within one
                                              # minor of the clusters you talk to (kubectl skew policy);
                                              # upstream supports only the newest three. https://kubernetes.io/releases/
INSTALL_HELM="${INSTALL_HELM:-true}"
INSTALL_K9S="${INSTALL_K9S:-true}"
INSTALL_KUBECTX="${INSTALL_KUBECTX:-true}"
INSTALL_KUBELOGIN="${INSTALL_KUBELOGIN:-true}"    # Entra ID credential plugin — required by kubectl against AKS
INSTALL_STARSHIP="${INSTALL_STARSHIP:-true}"
STARSHIP_PRESET="${STARSHIP_PRESET:-nerd-font-symbols}"   # `starship preset --list`; empty keeps the built-in default

# Modern CLI tools (shell experience)
INSTALL_ZOXIDE="${INSTALL_ZOXIDE:-true}"            # smart cd (z / zi)
INSTALL_BAT="${INSTALL_BAT:-true}"                  # cat with syntax highlighting (bat shim over batcat)
INSTALL_EZA="${INSTALL_EZA:-true}"                  # modern ls with icons
INSTALL_DELTA="${INSTALL_DELTA:-true}"              # git-delta: nicer diffs (wires git core.pager)
INSTALL_LAZYGIT="${INSTALL_LAZYGIT:-true}"          # git TUI
INSTALL_STERN="${INSTALL_STERN:-true}"              # multi-pod Kubernetes log tailing
INSTALL_GLOW="${INSTALL_GLOW:-true}"                # rendered markdown in the terminal
INSTALL_ZSH_PLUGINS="${INSTALL_ZSH_PLUGINS:-true}"  # zsh-autosuggestions + zsh-syntax-highlighting
INSTALL_OMZ="${INSTALL_OMZ:-true}"                  # oh-my-zsh: framework only (completion, git aliases,
                                                    # tab-title support). Starship stays the prompt, so
                                                    # ZSH_THEME is forced empty — see ensure_omz.
OMZ_PLUGINS="${OMZ_PLUGINS:-git zsh-autosuggestions zsh-syntax-highlighting}"
# Plugins omz loads from its own custom/plugins clones (upstream tracks newer than apt —
# the apt zsh-autosuggestions is 0.7.0 and suggests less). Cloned by ensure_omz, pulled by
# update-ubuntu.sh. ensure_zsh_plugins falls back to the apt packages when a clone is
# absent, and never sources one that omz already loads.
OMZ_CUSTOM_PLUGINS=(
  "zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions"
  "zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting"
)

# Shell history + inline suggestion UX (the zsh counterpart of the Windows
# PSReadLine block). Off-by-default zsh keeps 1000 lines and oh-my-zsh raises that
# to only SAVEHIST=10000, which silently truncates the history file on every write.
CONFIGURE_SHELL_HISTORY="${CONFIGURE_SHELL_HISTORY:-true}"
SHELL_HISTORY_SIZE="${SHELL_HISTORY_SIZE:-200000}"          # HISTSIZE/SAVEHIST for zsh, HISTSIZE/HISTFILESIZE for bash
# zsh-autosuggestions defaults to fg=8 ("bright black"), which sits a shade off the
# background on the OneHalfDark/Windows Terminal palettes and reads as no suggestion
# at all. Same problem, same fix as PSReadLine's InlinePrediction colour on Windows.
ZSH_AUTOSUGGEST_COLOR="${ZSH_AUTOSUGGEST_COLOR:-fg=#7f849c}"

INSTALL_NODE="${INSTALL_NODE:-true}"             # Node via fnm (per-project versions; see ensure_node)
NODE_MAJOR_VERSION="${NODE_MAJOR_VERSION:-24}"   # fnm default. Active LTS (22 reached EOL Sep 2026);
                                                 # https://nodejs.org/en/about/previous-releases
FNM_DIR="${FNM_DIR:-$HOME/.local/share/fnm}"     # fnm binary + every Node version it installs
NPM_GLOBAL_PREFIX="${NPM_GLOBAL_PREFIX:-$HOME/.local}"   # npm -g target shared by all Node versions;
                                                         # binaries land in $NPM_GLOBAL_PREFIX/bin
MIGRATE_LEGACY_NODE="${MIGRATE_LEGACY_NODE:-ask}"      # ask | yes | no — move off apt nodejs / NodeSource / nvm
                                                         # and old root-owned npm globals (see migrate_legacy_node)

# Agentic CLIs.
# Claude Code comes from its own installer (ensure_claude_code) and needs no Node.
# Codex is an npm global installed by ensure_node (so it needs INSTALL_NODE): it
# lands in NPM_GLOBAL_PREFIX like ncu does, and `update-ubuntu.sh` bumps it with
# the other globals.
INSTALL_CLAUDE_CODE="${INSTALL_CLAUDE_CODE:-true}"   # `claude` — native install, self-updating
INSTALL_CODEX="${INSTALL_CODEX:-true}"               # `codex`  — @openai/codex
CONFIGURE_WSL_CONF="${CONFIGURE_WSL_CONF:-true}"   # set false on native Linux (not WSL)
WSL_ENABLE_SYSTEMD="${WSL_ENABLE_SYSTEMD:-true}"   # requires Windows 11 22H2+ / WSL 2.0
SET_ZSH_DEFAULT="${SET_ZSH_DEFAULT:-true}"
SET_GIT_DEFAULTS="${SET_GIT_DEFAULTS:-true}"
ENSURE_SSH_KEY="${ENSURE_SSH_KEY:-true}"
INSTALL_DOTNET="${INSTALL_DOTNET:-true}"
DOTNET_SDK_VERSION="${DOTNET_SDK_VERSION:-10.0}"  # current LTS, supported to Nov 2028. 8.0 is the previous
                                                  # LTS and leaves support Nov 2026; https://dotnet.microsoft.com/download
INSTALL_ASPIRE="${INSTALL_ASPIRE:-true}"          # `aspire` CLI from aspire.dev (needs a .NET SDK to run an AppHost)
INSTALL_AZD="${INSTALL_AZD:-true}"                # `azd` — Azure Developer CLI; provisions and deploys an Aspire AppHost
INSTALL_DOTNET_TOOLS="${INSTALL_DOTNET_TOOLS:-true}"  # .NET global tools (dotnet-outdated — the NuGet counterpart to ncu)
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

gh_latest_tag() {
  curl -fsSL "https://api.github.com/repos/${1}/releases/latest" \
    | grep '"tag_name"' | cut -d'"' -f4
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

# kubelogin — the Entra ID credential plugin kubectl shells out to. An AKS cluster
# with Entra integration hands back a kubeconfig whose user block is `exec:
# kubelogin`, so without this binary every kubectl call against such a cluster
# fails on the exec step. kubectl alone is not enough, which is why this sits
# beside ensure_kubectl rather than being optional.
ensure_kubelogin() {
  if ensure_command kubelogin; then
    echo "✓ kubelogin already installed"
    return
  fi
  echo "→ Installing kubelogin (latest)"
  local version dpkg_arch tmp
  version=$(gh_latest_tag Azure/kubelogin)   # e.g. v0.2.13
  dpkg_arch=$(dpkg --print-architecture)     # amd64 / arm64 — matches kubelogin's asset naming
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/Azure/kubelogin/releases/download/${version}/kubelogin-linux-${dpkg_arch}.zip" \
    -o "$tmp/kubelogin.zip"
  # The archive nests the binary under bin/linux_<arch>/; -j flattens that away.
  unzip -qo -j "$tmp/kubelogin.zip" "bin/linux_${dpkg_arch}/kubelogin" -d "$tmp"
  sudo install -m 0755 "$tmp/kubelogin" /usr/local/bin/kubelogin
  rm -rf "$tmp"
  echo "✓ kubelogin ${version} installed"
}

# Node comes from fnm, not apt. Client repos pin their own Node (.nvmrc,
# .node-version, package.json engines) and fnm switches on `cd`, without the
# shell-startup cost of sourcing nvm.sh. NODE_MAJOR_VERSION is only the *default*.
#
# Keyed on the pinned major rather than on `node` existing, like ensure_dotnet:
# fnm installs versions side by side, so bumping the pin and rerunning adds the
# new major and removes nothing. Moving the default onto it is a decision, not a
# refresh, so a rerun only reports that; `update-ubuntu.sh --pins` asks and moves it.
#
# npm globals go to NPM_GLOBAL_PREFIX rather than the active Node's own prefix.
# fnm gives every version its own, so globals would otherwise vanish on each patch
# update and inside any project whose .nvmrc selects another Node. It is
# user-owned, so no sudo, and the default (~/.local) drops the binaries into
# ~/.local/bin, which is already on PATH.

# Put fnm and its default Node on PATH for this (non-interactive) script. The rc
# block does the same for interactive shells.
activate_fnm() {
  [[ -x "$FNM_DIR/fnm" ]] || return 1
  export FNM_DIR
  case ":$PATH:" in *":$FNM_DIR:"*) ;; *) export PATH="$FNM_DIR:$PATH" ;; esac
  eval "$(fnm env --shell bash)"
}

# The version fnm's `default` alias points at (e.g. v24.21.0), or nothing.
fnm_default_version() {
  local link
  link="$(readlink "$FNM_DIR/aliases/default" 2>/dev/null)" || return 0
  basename "$(dirname "$link")"
}

# Looked up on disk, not through `npm root -g`: npm masks path segments that look
# like tokens (a UUID in the path prints as ***), which breaks any comparison.
npm_global_installed() {
  [[ -d "$NPM_GLOBAL_PREFIX/lib/node_modules/$1" ]]
}

ensure_fnm_shell_init() {
  local body rc shell fnm_dir="$FNM_DIR"
  # Written as $HOME/... when under the home directory, so the block reads the
  # same on every machine and the audit can compare it.
  [[ "$fnm_dir" == "$HOME/"* ]] && fnm_dir="\$HOME/${fnm_dir#"$HOME"/}"
  body="$(mktemp)"
  for pair in ".bashrc:bash" ".zshrc:zsh"; do
    rc="$HOME/${pair%%:*}"; shell="${pair##*:}"
    [[ -f "$rc" ]] || continue
    cat > "$body" <<FNMRC
# Node version manager. --use-on-cd switches Node on entering a directory that
# carries .nvmrc / .node-version / package.json engines; elsewhere the fnm
# default applies. npm globals live in one prefix shared by every version (~/.npmrc).
if [ -x "$fnm_dir/fnm" ]; then
  export FNM_DIR="$fnm_dir"
  export PATH="\$FNM_DIR:\$PATH"
  eval "\$(fnm env --use-on-cd --shell $shell)"
fi
FNMRC
    if ! set_managed_block "$rc" "fnm" "$body" "fnm"; then
      echo "→ Adding fnm init to $(basename "$rc")"
      wrap_managed_block "fnm" "$body" >> "$rc"
    fi
  done
  rm -f "$body"
}

# Earlier Node installs fnm supersedes: apt's nodejs, NodeSource, nvm, and globals
# in the root-owned prefix those used. Each is left alone unless you say so —
# purging apt's nodejs takes its reverse dependencies with it, and the nvm lines
# are your own rc edits — so every step asks first (MIGRATE_LEGACY_NODE: ask |
# yes | no). audit-ubuntu.sh reports whatever is left as drift.
confirm_migrate() {
  local reply
  case "$MIGRATE_LEGACY_NODE" in
    yes) return 0 ;;
    no)  echo "  skipped (MIGRATE_LEGACY_NODE=no)"; return 1 ;;
  esac
  if [[ ! -t 0 ]]; then
    echo "  ⚠ no terminal to prompt on — skipped (MIGRATE_LEGACY_NODE=yes to run unattended)"
    return 1
  fi
  read -r -p "  $1 [y/N] " reply || return 1
  [[ "$reply" == "y" || "$reply" == "Y" ]] || { echo "  skipped"; return 1; }
}

# Package names installed in a node_modules dir, scoped ones as @scope/name.
list_global_pkgs() {
  local dir="$1" entry sub
  for entry in "$dir"/*; do
    [[ -d "$entry" ]] || continue
    case "${entry##*/}" in
      npm|corepack) ;;
      @*) for sub in "$entry"/*; do [[ -d "$sub" ]] && echo "${entry##*/}/${sub##*/}"; done ;;
      *)  echo "${entry##*/}" ;;
    esac
  done
}

migrate_legacy_node() {
  local dir bin pkgs pkg rc apt_pkgs n

  # 1. Globals first, while their old Node still exists to have installed them:
  #    reinstall each into NPM_GLOBAL_PREFIX under fnm, then drop the old copy and
  #    its bin links. Nothing is lost — anything you had, you keep.
  for dir in /usr/local/lib/node_modules /usr/lib/node_modules; do
    [[ "$dir" == "$NPM_GLOBAL_PREFIX/lib/node_modules" ]] && continue
    mapfile -t pkgs < <(list_global_pkgs "$dir")
    [[ ${#pkgs[@]} -gt 0 ]] || continue
    bin="${dir%/lib/node_modules}/bin"
    echo "→ npm globals in the old root-owned prefix $dir: ${pkgs[*]}"
    if confirm_migrate "Reinstall them into $NPM_GLOBAL_PREFIX and remove the old copies?"; then
      for pkg in "${pkgs[@]}"; do
        npm_global_installed "$pkg" || npm install -g "$pkg"
        sudo find "$bin" -maxdepth 1 -type l -lname "*node_modules/$pkg/*" -delete
        sudo rm -rf "${dir:?}/$pkg"
      done
      sudo find "$dir" -mindepth 1 -maxdepth 1 -type d -name '@*' -empty -delete
      hash -r
      echo "✓ globals moved to $NPM_GLOBAL_PREFIX"
    fi
  done

  # 2. nvm: its rc lines (backed up first) and its directory. fnm's block already
  #    wins PATH, so this only buys back the shell-startup time.
  local nvm_rcs=()
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f "$rc" ]] && grep -q 'NVM_DIR' "$rc" && nvm_rcs+=("$rc")
  done
  if [[ ${#nvm_rcs[@]} -gt 0 || -d "$HOME/.nvm" ]]; then
    echo "→ nvm still installed${nvm_rcs[*]:+ and loaded from ${nvm_rcs[*]##*/}}"
    if confirm_migrate "Remove the NVM_DIR lines and ~/.nvm?"; then
      for rc in "${nvm_rcs[@]}"; do
        cp "$rc" "$rc.devbox-nvm.bak"
        sed -i '/NVM_DIR/d' "$rc"
        echo "✓ nvm lines removed from $(basename "$rc") (backup: $(basename "$rc").devbox-nvm.bak)"
      done
      rm -rf "$HOME/.nvm"
      echo "✓ ~/.nvm removed — open a new shell to drop it from PATH"
    fi
  fi

  # 3. apt's nodejs (Ubuntu archive or NodeSource) and the NodeSource source.
  #    Purging nodejs also purges what depends on it (npm, apt builds of eslint,
  #    webpack, …), so the prompt states how many packages go.
  mapfile -t apt_pkgs < <(dpkg-query -W -f='${db:Status-Status} ${Package}\n' nodejs npm nodejs-doc libnode-dev 2>/dev/null \
    | awk '$1 == "installed" {print $2}')
  if [[ ${#apt_pkgs[@]} -gt 0 || -f /etc/apt/sources.list.d/nodesource.list ]]; then
    n=""
    # grep -c prints 0 itself on no match; `|| true` only stops pipefail aborting.
    [[ ${#apt_pkgs[@]} -gt 0 ]] && n=$(apt-get -s purge "${apt_pkgs[@]}" 2>/dev/null | grep -c '^Purg' || true)
    echo "→ apt Node still installed: ${apt_pkgs[*]:-(none)}${n:+ — purging removes $n package(s)}$([[ -f /etc/apt/sources.list.d/nodesource.list ]] && echo ', plus the NodeSource repo')"
    if confirm_migrate "Purge them?"; then
      [[ ${#apt_pkgs[@]} -gt 0 ]] && sudo apt-get purge -y "${apt_pkgs[@]}"
      sudo rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg
      hash -r
      echo "✓ apt Node removed (leftover libraries: sudo apt-get autoremove)"
    fi
  fi
}

ensure_node() {
  if activate_fnm; then
    echo "✓ fnm already installed ($(fnm --version))"
  else
    echo "→ Installing fnm"
    # --skip-shell: the installer would append an unmanaged block to one rc file;
    # ensure_fnm_shell_init writes a managed one to both.
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$FNM_DIR" --skip-shell
    activate_fnm
    echo "✓ fnm installed ($(fnm --version))"
  fi
  ensure_fnm_shell_init

  if fnm list 2>/dev/null | grep -qE "^\* v${NODE_MAJOR_VERSION}\."; then
    echo "✓ node ${NODE_MAJOR_VERSION}.x already installed (fnm)"
  else
    echo "→ Installing Node.js ${NODE_MAJOR_VERSION}.x (fnm)"
    fnm install "$NODE_MAJOR_VERSION"
  fi

  local default
  default="$(fnm_default_version)"
  if [[ -z "$default" ]]; then
    echo "→ Setting fnm default to ${NODE_MAJOR_VERSION}.x"
    fnm default "$NODE_MAJOR_VERSION"
  elif [[ "$default" == "v${NODE_MAJOR_VERSION}."* ]]; then
    echo "✓ fnm default is $default"
  else
    echo "⚠ fnm default is $default, pin is ${NODE_MAJOR_VERSION}.x — move it with: bash update-ubuntu.sh --pins"
  fi
  # Re-evaluate: the multishell link fnm env made above predates any default.
  activate_fnm

  # Read from ~/.npmrc: npm refuses `npm config get prefix` ("protected"), and
  # `npm prefix -g` output is masked as npm_global_installed explains.
  if grep -qxF "prefix=$NPM_GLOBAL_PREFIX" "$HOME/.npmrc" 2>/dev/null; then
    echo "✓ npm global prefix is $NPM_GLOBAL_PREFIX"
  else
    echo "→ Setting npm global prefix to $NPM_GLOBAL_PREFIX (~/.npmrc)"
    mkdir -p "$NPM_GLOBAL_PREFIX"
    npm config set prefix "$NPM_GLOBAL_PREFIX"
  fi

  migrate_legacy_node

  # Checked in the prefix rather than on PATH: a copy left in an old root-owned
  # prefix would otherwise count as installed here.
  # The literal `npm install -g <package>` calls below are what audit-ubuntu.sh
  # greps out as the expected set of globals — keep them literal, not built from a
  # variable, or the audit reports every global as unexpected drift.
  if npm_global_installed npm-check-updates; then
    echo "✓ ncu already installed"
  else
    echo "→ Installing ncu (npm-check-updates)"
    npm install -g npm-check-updates
    echo "✓ ncu installed"
  fi

  if [[ "$INSTALL_CODEX" == "true" ]]; then
    if npm_global_installed @openai/codex; then
      echo "✓ Codex already installed"
    else
      echo "→ Installing Codex (@openai/codex)"
      npm install -g @openai/codex
      echo "✓ Codex installed — run 'codex' to sign in"
    fi
  fi
}

# Claude Code, from Anthropic's installer rather than as an npm global. The native
# install lands in ~/.local/bin and updates itself in the background, which is the
# upstream-recommended path, and it does not tie `claude` to whichever Node fnm
# has active. No Node dependency either — npm ships the same native binary, it
# just wraps it in a package.
ensure_claude_code() {
  # Migrate machines set up before this switch: two installs on one PATH means the
  # winner is whichever directory comes first, and only the native one can update
  # itself. `hash -r` so the shell forgets the just-removed /usr/bin/claude.
  # `npm ls -g` exits non-zero on unrelated grumbles (extraneous deps), and with
  # pipefail that would swallow a match — so capture first, match second.
  local npm_globals=""
  ensure_command npm && npm_globals="$(npm ls -g --depth=0 --parseable 2>/dev/null || true)"
  if [[ -n "$npm_globals" ]] && grep -q 'claude-code$' <<< "$npm_globals"; then
    echo "→ Removing the npm-global Claude Code (superseded by the native install)"
    npm uninstall -g @anthropic-ai/claude-code
    hash -r 2>/dev/null || true
  fi

  if ensure_command claude; then
    echo "✓ Claude Code already installed ($(claude --version 2>/dev/null | head -1)) — it self-updates"
    return
  fi
  echo "→ Installing Claude Code (native installer)"
  curl -fsSL https://claude.ai/install.sh | bash
  echo "✓ Claude Code installed — run 'claude' to sign in"
}

# Append `eval "$(<tool> init <shell>)"` to bash/zsh rc files (idempotent).
ensure_shell_init() {
  local tool="$1" marker="$2"   # marker: unique substring already present when wired
  for pair in ".bashrc:bash" ".zshrc:zsh"; do
    local rc="$HOME/${pair%%:*}" shell="${pair##*:}"
    [[ -f "$rc" ]] || continue
    if grep -q "$marker" "$rc"; then
      echo "✓ $tool already in $(basename "$rc")"
    else
      echo "→ Adding $tool init to $(basename "$rc")"
      printf '\neval "$(%s init %s)"\n' "$tool" "$shell" >> "$rc"
    fi
  done
}

ensure_zoxide() {
  if ensure_command zoxide; then
    echo "✓ zoxide already installed"
  else
    echo "→ Installing zoxide"
    curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh \
      | sh -s -- --bin-dir "$HOME/.local/bin"
  fi
  ensure_shell_init zoxide 'zoxide init'
}

ensure_bat() {
  ensure_pkg bat
  # Debian/Ubuntu ship the binary as batcat (name clash); provide a `bat` shim like fd.
  if ensure_command batcat && ! ensure_command bat; then
    if [[ -L "$HOME/.local/bin/bat" || -f "$HOME/.local/bin/bat" ]]; then
      echo "✓ bat shim already exists"
    else
      echo "→ Creating bat shim at ~/.local/bin/bat"
      mkdir -p "$HOME/.local/bin"
      ln -s "$(command -v batcat)" "$HOME/.local/bin/bat"
    fi
  fi
}

ensure_eza() {
  if ensure_command eza; then
    echo "✓ eza already installed"
  else
    echo "→ Installing eza (gierens apt repo)"
    sudo mkdir -p /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/gierens.gpg ]]; then
      curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
        | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
      sudo chmod 0644 /etc/apt/keyrings/gierens.gpg
    fi
    if [[ ! -f /etc/apt/sources.list.d/gierens.list ]]; then
      echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
        | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
      sudo apt-get update -y
    fi
    sudo apt-get install -y eza
    echo "✓ eza installed"
  fi

  # Convenience aliases: ls/ll/lt -> eza. `--icons=auto`, never a bare `--icons`:
  # since eza 0.20 the flag takes an optional value, so `ls somedir` would hand
  # "somedir" to --icons and fail with "invalid value ... for '--icons'".
  local body
  body="$(mktemp)"
  cat > "$body" <<'ALIASES'
alias ls='eza --icons=auto'
alias ll='eza -la --icons=auto --git'
alias lt='eza --tree --level=2 --icons=auto'
ALIASES
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f "$rc" ]] || continue
    migrate_legacy_eza_block "$rc"
    if ! set_managed_block "$rc" "eza aliases" "$body" "eza aliases"; then
      echo "→ Adding eza aliases to $(basename "$rc")"
      wrap_managed_block "eza aliases" "$body" >> "$rc"
    fi
  done
  rm -f "$body"
}

# Earlier runs wrote a bare '# devbox eza aliases' line followed by the aliases,
# append-if-absent — so a changed alias never reached an existing machine. Wrap
# that legacy block in the managed delimiters where it sits, so set_managed_block
# can rewrite it in place from now on.
migrate_legacy_eza_block() {
  local rc="$1" tmp
  grep -qxF '# devbox eza aliases' "$rc" || return 0
  echo "→ Converting legacy eza aliases block in $(basename "$rc") to a managed block"
  tmp="$(mktemp)"
  awk -v endmark="$MANAGED_END" '
    $0 == "# devbox eza aliases" { print "# --- devbox: eza aliases ---"; inblock = 1; next }
    inblock && /^alias (ls|ll|lt)=/ { print; next }
    inblock { print endmark; inblock = 0 }
    { print }
    END { if (inblock) print endmark }
  ' "$rc" > "$tmp"
  mv "$tmp" "$rc"
}

ensure_delta() {
  if ensure_command delta; then
    echo "✓ delta already installed"
  else
    echo "→ Installing git-delta (latest)"
    local version dpkg_arch arch
    version=$(gh_latest_tag dandavison/delta)   # tags have no leading 'v' (e.g. 0.18.2)
    dpkg_arch=$(dpkg --print-architecture)
    arch=$([ "$dpkg_arch" = "amd64" ] && echo "x86_64" || echo "aarch64")
    curl -fsSL "https://github.com/dandavison/delta/releases/download/${version}/delta-${version}-${arch}-unknown-linux-gnu.tar.gz" \
      | sudo tar -xz --strip-components=1 -C /usr/local/bin "delta-${version}-${arch}-unknown-linux-gnu/delta"
    echo "✓ delta ${version} installed"
  fi
  # Wire delta into git as the diff pager (idempotent)
  ensure_git_config "core.pager" "delta"
  ensure_git_config "interactive.diffFilter" "delta --color-only"
  ensure_git_config "delta.navigate" "true"
}

ensure_lazygit() {
  if ensure_command lazygit; then
    echo "✓ lazygit already installed"
    return
  fi
  echo "→ Installing lazygit (latest)"
  local version num dpkg_arch arch
  version=$(gh_latest_tag jesseduffield/lazygit)   # e.g. v0.44.1
  num="${version#v}"
  dpkg_arch=$(dpkg --print-architecture)
  arch=$([ "$dpkg_arch" = "amd64" ] && echo "x86_64" || echo "arm64")
  curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/${version}/lazygit_${num}_Linux_${arch}.tar.gz" \
    | sudo tar -xz -C /usr/local/bin lazygit
  echo "✓ lazygit ${version} installed"
}

ensure_stern() {
  if ensure_command stern; then
    echo "✓ stern already installed"
    return
  fi
  echo "→ Installing stern (latest)"
  local version num dpkg_arch
  version=$(gh_latest_tag stern/stern)   # e.g. v1.30.0
  num="${version#v}"
  dpkg_arch=$(dpkg --print-architecture)   # amd64 / arm64 — matches stern's asset naming
  curl -fsSL "https://github.com/stern/stern/releases/download/${version}/stern_${num}_linux_${dpkg_arch}.tar.gz" \
    | sudo tar -xz -C /usr/local/bin stern
  echo "✓ stern ${version} installed"
}

ensure_glow() {
  if ensure_command glow; then
    echo "✓ glow already installed"
    return
  fi
  echo "→ Installing glow (latest)"
  local version num dpkg_arch arch dir
  version=$(gh_latest_tag charmbracelet/glow)   # e.g. v3.0.0
  num="${version#v}"
  dpkg_arch=$(dpkg --print-architecture)
  arch=$([ "$dpkg_arch" = "amd64" ] && echo "x86_64" || echo "arm64")
  dir="glow_${num}_Linux_${arch}"   # the tarball wraps the binary in this directory
  curl -fsSL "https://github.com/charmbracelet/glow/releases/download/${version}/${dir}.tar.gz" \
    | sudo tar -xz --strip-components=1 -C /usr/local/bin "${dir}/glow"
  echo "✓ glow ${version} installed"
}

# oh-my-zsh is the zsh *framework* (completion defaults, git aliases, the
# termsupport hooks that title the tab) — not the prompt. Starship renders the
# prompt, and its init runs after omz, so any ZSH_THEME is built and thrown away:
# ensure_omz forces it empty. Run this before ensure_zsh_plugins/ensure_starship
# so the appended blocks end up in load order.
ensure_omz() {
  is_pkg_installed zsh || { echo "✓ zsh not installed, skipping oh-my-zsh"; return; }
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    echo "✓ oh-my-zsh already installed"
  else
    echo "→ Installing oh-my-zsh"
    # KEEP_ZSHRC stops the installer replacing an existing .zshrc with its template
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi

  [[ -f "$HOME/.zshrc" ]] || return

  if grep -q 'oh-my-zsh.sh' "$HOME/.zshrc"; then
    echo "✓ oh-my-zsh already sourced in .zshrc"
  else
    echo "→ Adding oh-my-zsh block to .zshrc"
    cat >> "$HOME/.zshrc" <<OMZ

# devbox oh-my-zsh — framework only; starship (below) renders the prompt
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=($OMZ_PLUGINS)
source \$ZSH/oh-my-zsh.sh
OMZ
  fi

  local theme_line
  theme_line=$(grep -m1 '^ZSH_THEME=' "$HOME/.zshrc" || true)
  if [[ -z "$theme_line" ]] || [[ "$theme_line" == 'ZSH_THEME=""'* ]] || [[ "$theme_line" == "ZSH_THEME=''"* ]]; then
    echo "✓ ZSH_THEME already empty (starship owns the prompt)"
  else
    echo "→ Clearing ${theme_line} (starship owns the prompt)"
    sed -i 's|^ZSH_THEME=.*|ZSH_THEME=""   # starship renders the prompt; an omz theme would be discarded|' \
      "$HOME/.zshrc"
  fi

  # Clone the zsh-users plugins omz loads from custom/plugins
  local entry name url dest
  for entry in "${OMZ_CUSTOM_PLUGINS[@]}"; do
    name="${entry%% *}"; url="${entry#* }"
    dest="$HOME/.oh-my-zsh/custom/plugins/$name"
    if [[ -d "$dest" ]]; then
      echo "✓ omz plugin already cloned: $name"
    else
      echo "→ Cloning omz plugin: $name"
      git clone --depth=1 --quiet "$url" "$dest"
    fi
  done

  # Add anything from OMZ_PLUGINS the plugins=(...) line is missing. Only ever adds,
  # so hand-added plugins survive a rerun. Compared as whole words against the
  # existing list — a substring match would re-add "git" to plugins=(git).
  local want list missing=()
  list=$(sed -n 's|^plugins=(\(.*\))|\1|p' "$HOME/.zshrc" | head -1)
  for want in $OMZ_PLUGINS; do
    [[ " $list " == *" $want "* ]] || missing+=("$want")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "→ Adding to omz plugins: ${missing[*]}"
    sed -i "s|^plugins=(\(.*\))|plugins=(\1 ${missing[*]})|" "$HOME/.zshrc"
  else
    echo "✓ omz plugins list already has: $OMZ_PLUGINS"
  fi
}

# Fallback loader for the zsh-users plugins. oh-my-zsh loads them from its
# custom/plugins clones when ensure_omz ran, so this only installs the apt packages
# and sources them when a clone is absent — sourcing one omz already loads would
# double the work, and (for autosuggestions) leave two sets of wrapped widgets.
ensure_zsh_plugins() {
  is_pkg_installed zsh || { echo "✓ zsh not installed, skipping plugins"; return; }
  [[ -f "$HOME/.zshrc" ]] || return
  # autosuggestions first: zsh-syntax-highlighting must be sourced last
  local name
  for name in zsh-autosuggestions zsh-syntax-highlighting; do
    local file="/usr/share/$name/$name.zsh"
    if [[ -d "$HOME/.oh-my-zsh/custom/plugins/$name" ]] \
       && grep -qE "^plugins=\(.*${name}" "$HOME/.zshrc"; then
      echo "✓ $name loaded by oh-my-zsh"
      continue
    fi
    ensure_pkg "$name"
    if grep -q "$name.zsh" "$HOME/.zshrc"; then
      echo "✓ $name already sourced in .zshrc"
    elif [[ -f "$file" ]]; then
      echo "→ Sourcing $name in .zshrc"
      printf '\nsource %s\n' "$file" >> "$HOME/.zshrc"
    fi
  done
}

MANAGED_END='# --- end devbox block ---'

# Rewrite the body of an existing '# --- devbox: <marker> ---' block IN PLACE,
# leaving the block where it already sits. Returns 1 when the block is absent, so
# the caller decides where a first-time block goes.
#
# In place matters twice over here: marker-presence-only checks strand every
# existing machine on the old block the moment the snippet changes (see
# Set-ManagedProfileBlock on the Windows side), and for the zsh history blocks the
# *position* is load-bearing — a delete-and-reappend would land the block on the
# wrong side of oh-my-zsh or fzf and silently stop working.
set_managed_block() {
  local file="$1" marker="$2" body_file="$3" label="$4"
  local begin="# --- devbox: ${marker} ---" tmp
  grep -qxF "$begin" "$file" || return 1

  tmp="$(mktemp)"
  awk -v begin="$begin" -v endmark="$MANAGED_END" -v bodyfile="$body_file" '
    $0 == begin {
      print
      while ((getline line < bodyfile) > 0) print line
      close(bodyfile); inblock = 1; next
    }
    inblock && $0 == endmark { print; inblock = 0; next }
    inblock { next }
    { print }
  ' "$file" > "$tmp"

  if cmp -s "$tmp" "$file"; then
    echo "✓ $label already current in $(basename "$file")"
    rm -f "$tmp"
  else
    echo "→ Rewriting $label block in $(basename "$file")"
    mv "$tmp" "$file"
  fi
}

# Wrap a body in the managed delimiters, ready to splice or append.
wrap_managed_block() {
  local marker="$1" body_file="$2"
  printf '\n# --- devbox: %s ---\n' "$marker"
  cat "$body_file"
  printf '%s\n' "$MANAGED_END"
}

# Splice a block into a file immediately BEFORE the first line containing a literal
# anchor substring; append to the end when no line contains it. Needed because `>>`
# can only ever put a load-order-sensitive block in the wrong place.
#
# The anchor is matched with index(), not a regex: awk mangles the `\$` in an
# anchor like `\$ZSH/oh-my-zsh.sh` into a bare `$`, which is an end-of-line anchor
# in ERE and matches nothing — the splice then silently drops the block.
insert_before_anchor() {
  local file="$1" anchor="$2" block_file="$3" tmp
  tmp="$(mktemp)"
  awk -v anchor="$anchor" -v blockfile="$block_file" '
    function emit(  line) { while ((getline line < blockfile) > 0) print line; close(blockfile) }
    !spliced && index($0, anchor) { emit(); spliced = 1 }
    { print }
    END { if (!spliced) emit() }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
  rm -f "$tmp"
}

# History retention + PSReadLine-style inline suggestion UX for zsh, and history
# retention for bash. Three managed blocks, two of them load-order sensitive:
#
#   1. "zsh history" MUST sit above `source $ZSH/oh-my-zsh.sh`. omz's
#      lib/history.zsh assigns HISTSIZE/SAVEHIST unconditionally, and
#      zsh-autosuggestions only honours ZSH_AUTOSUGGEST_* variables that are
#      already set at the moment the plugin loads.
#   2. "zsh history keys" MUST sit below the fzf integration, which binds ^I to
#      fzf-completion when it loads and would otherwise clobber the Tab widget
#      defined here.
#   3. "bash history" is a plain append — Ubuntu's stock .bashrc sets
#      HISTSIZE=1000/HISTFILESIZE=2000 near the top, so last assignment wins.
#
# Run this AFTER ensure_omz / ensure_fzf_shell_integration so both anchors exist.
ensure_shell_history() {
  local body wrapped
  body="$(mktemp)"; wrapped="$(mktemp)"

  if [[ -f "$HOME/.zshrc" ]]; then
    # Note: no literal 'source $ZSH/oh-my-zsh.sh' in these comments — the audit
    # locates that anchor by line number and a quoted copy would shadow the real one.
    cat > "$body" <<ZHIST
# Keep this block ABOVE the oh-my-zsh source line: omz's lib/history.zsh reassigns
# HISTSIZE/SAVEHIST, and zsh-autosuggestions only reads ZSH_AUTOSUGGEST_* that are
# already set at the moment the plugin loads.
HISTFILE="\$HOME/.zsh_history"
HISTSIZE=$SHELL_HISTORY_SIZE     # entries held in memory
SAVEHIST=$SHELL_HISTORY_SIZE     # entries written to disk; a smaller value truncates the file on every write
setopt EXTENDED_HISTORY          # record timestamps
setopt HIST_EXPIRE_DUPS_FIRST    # trim duplicates before unique commands
setopt HIST_IGNORE_SPACE         # a leading space keeps a command out of history
setopt HIST_FIND_NO_DUPS         # don't re-offer a duplicate while searching
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY             # append immediately and share across live shells
# Ghost text: the stock fg=8 is invisible on the dark themes this repo configures.
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='$ZSH_AUTOSUGGEST_COLOR'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)   # fall back to completion when history has no match
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=40              # stop suggesting on very long lines (latency)
ZHIST
    if ! set_managed_block "$HOME/.zshrc" "zsh history" "$body" "zsh history settings"; then
      echo "→ Adding zsh history settings to .zshrc (above the oh-my-zsh source, when present)"
      wrap_managed_block "zsh history" "$body" > "$wrapped"
      # Anchor on the path alone so both `source $ZSH/...` and `. $ZSH/...` match.
      insert_before_anchor "$HOME/.zshrc" '$ZSH/oh-my-zsh.sh' "$wrapped"
    fi

    cat > "$body" <<'ZKEYS'
# Keep this block BELOW the fzf integration, which binds ^I (Tab) to fzf-completion
# and would otherwise win. Mirrors the PowerShell side: → accepts the whole
# suggestion, Ctrl+→ one word, Ctrl+R lists the history.
bindkey '^[[C'    autosuggest-accept   # Right arrow: accept the whole suggestion
bindkey '^[[1;5C' forward-word         # Ctrl+Right: accept one word of it
bindkey '^ '      autosuggest-accept   # Ctrl+Space: accept (Right arrow is taken mid-line)
# Tab: take the ghost suggestion when one is showing, otherwise complete as usual.
_devbox_tab_accept_or_complete() {
  if [[ -n "$POSTDISPLAY" ]]; then
    zle autosuggest-accept
  elif (( ${+widgets[fzf-completion]} )); then
    zle fzf-completion
  else
    zle expand-or-complete
  fi
}
zle -N _devbox_tab_accept_or_complete
bindkey '^I' _devbox_tab_accept_or_complete
# Ctrl+R history picker — the closest thing zsh has to PSReadLine's ListView.
export FZF_CTRL_R_OPTS="--height=45% --layout=reverse --border --info=inline --prompt='history > '"
ZKEYS
    if ! set_managed_block "$HOME/.zshrc" "zsh history keys" "$body" "zsh history keybindings"; then
      echo "→ Adding zsh history keybindings to .zshrc"
      wrap_managed_block "zsh history keys" "$body" >> "$HOME/.zshrc"
    fi
  fi

  if [[ -f "$HOME/.bashrc" ]]; then
    cat > "$body" <<BHIST
# Ubuntu's stock .bashrc caps history at 1000/2000 lines near the top of the file;
# these later assignments win.
HISTSIZE=$SHELL_HISTORY_SIZE
HISTFILESIZE=$SHELL_HISTORY_SIZE
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT='%F %T '
shopt -s histappend cmdhist
# Flush after every command so a killed terminal doesn't lose the session.
case "\${PROMPT_COMMAND:-}" in
  *'history -a'*) ;;
  *) PROMPT_COMMAND="history -a\${PROMPT_COMMAND:+;\$PROMPT_COMMAND}" ;;
esac
BHIST
    if ! set_managed_block "$HOME/.bashrc" "bash history" "$body" "bash history settings"; then
      echo "→ Adding bash history settings to .bashrc"
      wrap_managed_block "bash history" "$body" >> "$HOME/.bashrc"
    fi
  fi

  rm -f "$body" "$wrapped"
}

ensure_starship() {
  # Install binary
  if ensure_command starship; then
    echo "✓ starship already installed"
  else
    echo "→ Installing starship"
    curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin"
    # Ensure ~/.local/bin is on PATH in all present shell rc files (idempotent)
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
      if [[ -f "$rc" ]] && ! grep -q '\.local/bin' "$rc"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
        echo "→ Added ~/.local/bin to PATH in $(basename "$rc")"
      fi
    done
  fi

  # Apply a preset once — never clobber an existing starship.toml the user may have edited
  local config_dir="$HOME/.config"
  local config_file="$config_dir/starship.toml"
  if [[ -f "$config_file" ]]; then
    echo "✓ starship config already present: $config_file"
  elif [[ -n "$STARSHIP_PRESET" ]]; then
    echo "→ Applying starship preset: $STARSHIP_PRESET"
    mkdir -p "$config_dir"
    # starship lives in ~/.local/bin, which may not be on PATH in this non-login shell yet
    if ! ensure_command starship; then export PATH="$HOME/.local/bin:$PATH"; fi
    starship preset "$STARSHIP_PRESET" -o "$config_file"
    echo "✓ Preset saved to $config_file"
  fi

  # Wire init into shell rc files (idempotent; starship init must run last, so append)
  if [[ -f "$HOME/.bashrc" ]] && ! grep -q 'starship init' "$HOME/.bashrc"; then
    echo "→ Adding starship init to .bashrc"
    printf '\neval "$(starship init bash)"\n' >> "$HOME/.bashrc"
  elif [[ -f "$HOME/.bashrc" ]]; then
    echo "✓ starship already in .bashrc"
  fi
  if [[ -f "$HOME/.zshrc" ]] && ! grep -q 'starship init' "$HOME/.zshrc"; then
    echo "→ Adding starship init to .zshrc"
    printf '\neval "$(starship init zsh)"\n' >> "$HOME/.zshrc"
  elif [[ -f "$HOME/.zshrc" ]]; then
    echo "✓ starship already in .zshrc"
  fi
}

# Report the cwd to the terminal on every prompt: OSC 7 (the cwd itself, which
# WezTerm reads for tab titles and new-pane inheritance) plus OSC 0 (the title,
# which Windows Terminal and VS Code use as the tab label). Ubuntu's default PS1
# carries an OSC 0 escape, but starship replaces PS1 outright, so without this
# the tab reads "bash". Prepended to PROMPT_COMMAND at shell start, which keeps
# starship's and zoxide's own hooks intact.
ensure_terminal_cwd() {
  for pair in ".bashrc:bash" ".zshrc:zsh"; do
    local rc_file="${pair%%:*}" shell="${pair##*:}" rc="$HOME/${pair%%:*}"
    [[ -f "$rc" ]] || continue
    if grep -q 'devbox terminal cwd' "$rc"; then
      echo "✓ Terminal cwd/title reporting already in $rc_file"
      continue
    fi
    echo "→ Adding terminal cwd/title reporting to $rc_file"
    if [[ "$shell" == "bash" ]]; then
      cat >> "$rc" <<'TERMCWD'

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
TERMCWD
    else
      cat >> "$rc" <<'TERMCWD'

# devbox terminal cwd — report the cwd (OSC 7) and the tab title (OSC 0).
# oh-my-zsh's termsupport already does both; leave it alone when it is loaded.
__devbox_term_cwd() {
  local leaf="${PWD##*/}"
  printf '\033]7;file://%s%s\033\\' "${HOST:-localhost}" "$PWD"
  printf '\033]0;%s\007' "${leaf:-/}"
}
autoload -Uz add-zsh-hook
(( ${+functions[omz_termsupport_precmd]} )) || add-zsh-hook precmd __devbox_term_cwd
TERMCWD
    fi
  done
}

# Keyed on the pinned SDK, not on "is dotnet present at all". .NET SDKs install
# side by side, so bumping DOTNET_SDK_VERSION and rerunning adds the new one and
# leaves the old in place — nothing is removed and no project stops building.
# (ensure_node does the same for Node majors under fnm. kubectl cannot: its pin
# replaces the installed minor, so it stays guarded and is handled by
# `update-ubuntu.sh --pins`.)
ensure_dotnet() {
  if ensure_command dotnet && dotnet --list-sdks 2>/dev/null | grep -q "^${DOTNET_SDK_VERSION}\."; then
    echo "✓ dotnet SDK ${DOTNET_SDK_VERSION} already installed ($(dotnet --version 2>/dev/null))"
    return
  fi
  if ensure_command dotnet; then
    echo "→ dotnet present but SDK ${DOTNET_SDK_VERSION} is missing; installing it alongside"
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

# Aspire CLI. Installed from aspire.dev rather than as a `dotnet tool`: the payload
# is a self-contained build, so it neither tracks DOTNET_SDK_VERSION nor needs the
# SDK present to install (only `aspire run`/`publish` do).
#
# Two deliberate deviations from the upstream one-liner:
#   --skip-path — the installer appends an unmanaged `export PATH=` line to the rc
#     file of whichever shell it runs under. That is bash here, so zsh (the default
#     shell) would never see the CLI.
#   --install-path + a shim — the archive holds more than the binary
#     (Aspire.TypeSystem.xml rides along), so it cannot be dropped into a bin
#     directory wholesale. It keeps its own directory and gets a ~/.local/bin
#     symlink, the same shape as the bat/fd shims. /proc/self/exe resolves the
#     symlink, so the binary still finds its siblings.
ensure_aspire() {
  local bin_dir="$HOME/.aspire/bin"
  if ensure_command aspire; then
    echo "✓ aspire already installed ($(aspire --version 2>/dev/null | head -1))"
  elif [[ -x "$bin_dir/aspire" ]]; then
    echo "✓ aspire already installed ($("$bin_dir/aspire" --version 2>/dev/null | head -1)), not yet on PATH"
  else
    echo "→ Installing Aspire CLI"
    curl -fsSL https://aspire.dev/install.sh | bash -s -- --skip-path --install-path "$bin_dir"
    echo "✓ aspire installed ($("$bin_dir/aspire" --version 2>/dev/null | head -1))"
  fi

  # Shim into ~/.local/bin so both shells pick it up (idempotent).
  if [[ -x "$bin_dir/aspire" ]]; then
    if [[ -L "$HOME/.local/bin/aspire" ]]; then
      echo "✓ aspire shim already exists"
    else
      echo "→ Creating aspire shim at ~/.local/bin/aspire"
      mkdir -p "$HOME/.local/bin"
      ln -sf "$bin_dir/aspire" "$HOME/.local/bin/aspire"
    fi
  fi
}

# Azure Developer CLI (azd) — the provision-and-deploy half of the Aspire story:
# `azd init` over an AppHost generates the Bicep and wires it to Container Apps.
# From Microsoft's installer because there is no apt feed for it. Unlike
# ensure_aspire this needs no ~/.local/bin shim: the installer drops the payload
# in /opt/microsoft/azd and symlinks /usr/local/bin/azd, which is already on PATH.
# Run without sudo — the script elevates only the steps that need it, and running
# the whole thing as root would install against root's environment.
ensure_azd() {
  if ensure_command azd; then
    echo "✓ azd already installed ($(azd version 2>/dev/null | head -1))"
    return
  fi
  echo "→ Installing Azure Developer CLI (azd)"
  curl -fsSL https://aka.ms/install-azd.sh | bash
  echo "✓ azd installed ($(azd version 2>/dev/null | head -1))"
}

# Symlink a ~/.dotnet/tools binary into ~/.local/bin (idempotent).
ensure_dotnet_tool_shim() {
  local name="$1" src="$HOME/.dotnet/tools/$1"
  [[ -x "$src" ]] || return 0
  if [[ -L "$HOME/.local/bin/$name" ]]; then
    echo "✓ $name shim already exists"
    return
  fi
  echo "→ Creating $name shim at ~/.local/bin/$name"
  mkdir -p "$HOME/.local/bin"
  ln -sf "$src" "$HOME/.local/bin/$name"
}

# .NET global tools — the NuGet counterpart to the npm globals ensure_node installs:
# `dotnet outdated` is to a .csproj what `ncu` is to a package.json.
#
# Keep the `dotnet tool install -g <package>` calls literal, not built from a
# variable — audit-ubuntu.sh greps them out as the expected set, exactly as it does
# the npm globals.
#
# Tools land in ~/.dotnet/tools, which nothing here puts on PATH. Rather than add
# another rc-file PATH line, shim into ~/.local/bin, which ensure_starship already
# guarantees is on PATH — the same trade ensure_aspire makes. Should this list grow
# past a handful, one PATH entry becomes the better deal.
ensure_dotnet_tools() {
  if ! ensure_command dotnet; then
    echo "⚠ dotnet not installed; skipping .NET global tools"
    return
  fi

  # Checked three ways, like ensure_aspire: on PATH, then on disk but not yet on
  # PATH. Skipping that second case would re-run the install, and `dotnet tool
  # install` exits non-zero on an already-installed tool — fatal under `set -e`.
  if ensure_command dotnet-outdated; then
    echo "✓ dotnet-outdated already installed"
  elif [[ -x "$HOME/.dotnet/tools/dotnet-outdated" ]]; then
    echo "✓ dotnet-outdated already installed, not yet on PATH"
  else
    echo "→ Installing dotnet-outdated-tool"
    dotnet tool install -g dotnet-outdated-tool
    echo "✓ dotnet-outdated installed — run 'dotnet outdated' in a project"
  fi

  ensure_dotnet_tool_shim dotnet-outdated
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
[[ "$INSTALL_KUBELOGIN"  == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_STARSHIP"   == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_ZOXIDE"      == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_BAT"         == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_EZA"         == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_DELTA"       == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_LAZYGIT"     == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_STERN"       == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_GLOW"        == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_OMZ"         == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_ZSH_PLUGINS" == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$CONFIGURE_SHELL_HISTORY" == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_NODE"       == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_CLAUDE_CODE" == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_DOTNET"     == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_ASPIRE"     == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_AZD"        == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$INSTALL_DOTNET_TOOLS" == "true" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
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
# Ensure .zshrc exists so later sections (fd PATH, fzf, starship) can write to it
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

if [[ "$INSTALL_KUBELOGIN" == "true" ]]; then
  log "Installing kubelogin"
  ensure_kubelogin
fi

if [[ "$INSTALL_STARSHIP" == "true" ]]; then
  log "Installing starship"
  ensure_starship
fi

log "Configuring terminal cwd/title reporting (OSC 7 + OSC 0)"
ensure_terminal_cwd

if [[ "$INSTALL_ZOXIDE" == "true" ]]; then
  log "Installing zoxide"
  ensure_zoxide
fi

if [[ "$INSTALL_BAT" == "true" ]]; then
  log "Installing bat"
  ensure_bat
fi

if [[ "$INSTALL_EZA" == "true" ]]; then
  log "Installing eza"
  ensure_eza
fi

if [[ "$INSTALL_DELTA" == "true" ]]; then
  log "Installing git-delta"
  ensure_delta
fi

if [[ "$INSTALL_LAZYGIT" == "true" ]]; then
  log "Installing lazygit"
  ensure_lazygit
fi

if [[ "$INSTALL_STERN" == "true" ]]; then
  log "Installing stern"
  ensure_stern
fi

if [[ "$INSTALL_GLOW" == "true" ]]; then
  log "Installing glow"
  ensure_glow
fi

if [[ "$INSTALL_OMZ" == "true" ]]; then
  log "Installing oh-my-zsh (framework only — starship renders the prompt)"
  ensure_omz
fi

if [[ "$INSTALL_ZSH_PLUGINS" == "true" ]]; then
  log "Installing zsh plugins"
  ensure_zsh_plugins
fi

if [[ "$CONFIGURE_SHELL_HISTORY" == "true" ]]; then
  # After omz and fzf: this splices relative to both of their blocks.
  log "Configuring shell history and inline suggestions"
  ensure_shell_history
fi

if [[ "$INSTALL_NODE" == "true" ]]; then
  log "Installing fnm, Node.js and npm-global CLIs"
  ensure_node
fi

if [[ "$INSTALL_CLAUDE_CODE" == "true" ]]; then
  log "Installing Claude Code"
  ensure_claude_code
fi

if [[ "$INSTALL_DOTNET" == "true" ]]; then
  log "Installing .NET SDK"
  ensure_dotnet
fi

if [[ "$INSTALL_ASPIRE" == "true" ]]; then
  log "Installing Aspire CLI"
  ensure_aspire
fi

if [[ "$INSTALL_AZD" == "true" ]]; then
  log "Installing Azure Developer CLI"
  ensure_azd
fi

if [[ "$INSTALL_DOTNET_TOOLS" == "true" ]]; then
  log "Installing .NET global tools"
  ensure_dotnet_tools
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

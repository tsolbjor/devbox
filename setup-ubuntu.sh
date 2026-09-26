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
USE_WINDOWS_GCM="${USE_WINDOWS_GCM:-true}"        # HTTPS git auth via Git for Windows' Credential Manager
                                                  # (Entra/browser sign-in; Azure DevOps and GitHub)

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

# HTTPS remotes authenticate through the Windows Git Credential Manager that Git
# for Windows ships (setup-windows.ps1 installs it): browser/Entra sign-in, tokens
# kept in the Windows credential store, one login shared by both sides. The SSH
# key below still covers GitHub over SSH; Azure DevOps clients mostly hand out
# HTTPS URLs, which is where this earns its place.
ensure_git_credential_manager() {
  local gcm="/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"
  if [[ ! -x "$gcm" ]]; then
    echo "⚠ Git Credential Manager not found at $gcm — install Git for Windows (setup-windows.ps1), then rerun"
    return
  fi
  # credential.helper is run through the shell, so the space must stay escaped.
  ensure_git_config "credential.helper" "${gcm// /\\ }"
  # Azure Repos scopes credentials per organisation, which lives in the URL path.
  # Scoped to dev.azure.com rather than set globally: a global useHttpPath makes
  # GCM store (and prompt for) a separate GitHub credential per repository.
  ensure_git_config "credential.https://dev.azure.com.useHttpPath" "true"
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

# Latest release tag of a GitHub repo, or a non-zero return with a reason.
# Unauthenticated, the API allows 60 calls/hour per IP — a corporate NAT shares
# that budget with everyone behind it, and an empty tag would otherwise build a
# URL like .../download//k9s_... that fails with an unrelated-looking curl/tar
# error. So authenticate when a token is to hand, and fail clearly when not.
gh_latest_tag() {
  local repo="$1" tag token="${GITHUB_TOKEN:-${GH_TOKEN:-}}" auth=()
  if [[ -z "$token" ]] && ensure_command gh; then
    token="$(gh auth token 2>/dev/null || true)"
  fi
  [[ -n "$token" ]] && auth=(-H "Authorization: Bearer $token")
  tag="$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
    | grep '"tag_name"' | cut -d'"' -f4)" || true
  if [[ -z "$tag" ]]; then
    echo "⚠ Could not resolve the latest ${repo} release — GitHub API rate limit or no network?" >&2
    echo "  Authenticate and rerun: export GITHUB_TOKEN=... or run 'gh auth login'" >&2
    return 1
  fi
  printf '%s\n' "$tag"
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

# Helm's apt repo moved from baltocdn.com to Buildkite, with a new signing key.
# The old host now serves an incomplete TLS chain, so a machine still carrying
# its source fails *every* `apt-get update`, not just helm's — hence the source
# is migrated even when helm is already installed.
ensure_helm() {
  local list=/etc/apt/sources.list.d/helm-stable-debian.list key=/usr/share/keyrings/helm.gpg
  local migrate=false
  if [[ -f "$list" ]] && grep -q 'baltocdn' "$list"; then
    echo "→ Moving the helm apt source off the retired baltocdn.com to Buildkite"
    sudo rm -f "$list" "$key"
    migrate=true
  fi
  if ensure_command helm && [[ "$migrate" == "false" ]]; then
    echo "✓ helm already installed"
    return
  fi
  if [[ ! -f "$key" ]]; then
    curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey \
      | gpg --dearmor | sudo tee "$key" > /dev/null
  fi
  if [[ ! -f "$list" ]]; then
    echo "deb [signed-by=$key] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
      | sudo tee "$list" > /dev/null
    sudo apt-get update -y
  fi
  if ensure_command helm; then
    echo "✓ helm already installed; apt source migrated"
    return
  fi
  echo "→ Installing helm"
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
  version=$(gh_latest_tag derailed/k9s)
  arch=$(dpkg --print-architecture)
  curl -fsSL "https://github.com/derailed/k9s/releases/download/${version}/k9s_Linux_${arch}.tar.gz" \
    | sudo tar -xz -C /usr/local/bin k9s
  echo "✓ k9s ${version} installed"
}


# Set `key = value` under [section] of an INI file IN PLACE, leaving every other
# line alone: an existing key is rewritten where it sits, a missing one is added at
# the end of its section, a missing section is appended. A key that already holds
# the value keeps its original spelling (`key=value` vs `key = value`).
# Returns 0 when the file changed, 1 when it already matched.
ini_set() {
  local file="$1" section="$2" key="$3" value="$4" tmp
  tmp="$(mktemp)"
  awk -v sec="$section" -v key="$key" -v val="$value" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function flush() { if (insec && !done) { print key " = " val; done = 1 } }
    /^[[:space:]]*\[.*\][[:space:]]*$/ {
      flush()
      s = trim($0); s = substr(s, 2, length(s) - 2)
      insec = (trim(s) == sec); if (insec) seen = 1
      print; next
    }
    insec && !done && index($0, "=") {
      k = trim(substr($0, 1, index($0, "=") - 1))
      if (k == key) {
        v = trim(substr($0, index($0, "=") + 1))
        print (v == val ? $0 : key " = " val); done = 1; next
      }
    }
    { print }
    END {
      flush()
      if (!seen) { if (NR > 0) print ""; print "[" sec "]"; print key " = " val }
    }
  ' "$file" > "$tmp"
  if cmp -s "$tmp" "$file"; then rm -f "$tmp"; return 1; fi
  mv "$tmp" "$file"
}

# Merged key by key, never written wholesale: /etc/wsl.conf also carries settings
# this script does not own — notably `[user] default=<name>`, which the first-run
# setup of the newer tar-based WSL distros writes there. Dropping that line makes
# the distro log in as root on its next start.
ensure_wsl_conf() {
  local conf="/etc/wsl.conf" tmp changed=false
  tmp="$(mktemp)"
  if [[ -f "$conf" ]]; then cp "$conf" "$tmp"; fi
  ini_set "$tmp" automount options metadata && changed=true
  if [[ "$WSL_ENABLE_SYSTEMD" == "true" ]]; then
    ini_set "$tmp" boot systemd true && changed=true
  fi
  if [[ "$changed" == "false" ]]; then
    rm -f "$tmp"
    echo "✓ /etc/wsl.conf already matches desired settings"
    return
  fi
  echo "→ Updating /etc/wsl.conf (merging [automount]/[boot]; other settings kept)"
  sudo install -m 0644 "$tmp" "$conf"
  rm -f "$tmp"
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
  version=$(gh_latest_tag ahmetb/kubectx)
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

# Put fnm and its default Node on PATH for this (non-interactive) script.
# ~/.config/devbox/<shell>rc does the same for interactive shells.
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
    # ~/.config/devbox/<shell>rc initialises fnm for both shells.
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$FNM_DIR" --skip-shell
    activate_fnm
    echo "✓ fnm installed ($(fnm --version))"
  fi

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


ensure_zoxide() {
  if ensure_command zoxide; then
    echo "✓ zoxide already installed"
  else
    echo "→ Installing zoxide"
    curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh \
      | sh -s -- --bin-dir "$HOME/.local/bin"
  fi
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
# termsupport hooks that title the tab) — not the prompt. Installed here, loaded by
# ~/.config/devbox/zshrc with an empty ZSH_THEME, since starship renders the prompt.
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
}

# Fallback for the zsh-users plugins: the apt packages, for when oh-my-zsh has no
# clone of one. ~/.config/devbox/zshrc sources an apt copy only if omz is not
# already loading that plugin, so each loads exactly once.
ensure_zsh_plugins() {
  is_pkg_installed zsh || { echo "✓ zsh not installed, skipping plugins"; return; }
  local name
  for name in zsh-autosuggestions zsh-syntax-highlighting; do
    if [[ -d "$HOME/.oh-my-zsh/custom/plugins/$name" ]]; then
      echo "✓ $name comes from oh-my-zsh"
    else
      ensure_pkg "$name"
    fi
  done
}

# =========================
# Shell config: ~/.config/devbox/{zshrc,bashrc}
# =========================
#
# Everything setup configures for an interactive shell lives in ONE generated file
# per shell, rewritten whole on every run, and ~/.zshrc / ~/.bashrc carry only a
# "devbox: loader" block that sources it. Load order is then a property of a file
# this script owns outright: oh-my-zsh before the history settings it would
# otherwise override, fzf before the Tab binding it would otherwise clobber,
# starship last. (The previous design spliced a dozen blocks into the user's own
# rc file and had to audit their line positions to keep that order.)
#
# The file depends on nothing but the PARAMETERS above — no probing of what is
# installed — so `bash setup-ubuntu.sh --render-rc zsh` reproduces it exactly and
# audit-ubuntu.sh diffs against that. What is installed is checked when the shell
# starts instead: every section is guarded, so a removed tool never breaks a shell.

DEVBOX_RC_DIR="$HOME/.config/devbox"
MANAGED_END='# --- end devbox block ---'

render_devbox_rc() {
  local shell="$1" fnm_dir="$FNM_DIR"
  case "$shell" in
    zsh|bash) ;;
    *) echo "render_devbox_rc: unknown shell '$shell' (bash|zsh)" >&2; return 1 ;;
  esac
  # Written as $HOME/... when under the home directory, so the file reads the same
  # on every machine and for every user.
  [[ "$fnm_dir" == "$HOME/"* ]] && fnm_dir="\$HOME/${fnm_dir#"$HOME"/}"

  cat <<HEADER
# Generated by devbox (setup-ubuntu.sh) and rewritten on every run: edits here are lost.
# Sourced by the "devbox: loader" block in ~/.${shell}rc. Put your own settings in
# ~/.${shell}rc — lines above the loader run before this file, lines below it run
# after it and win. The section order below is load-bearing; each says why.

# ~/.local/bin holds starship, zoxide, claude and the fd/bat/aspire shims.
case ":\$PATH:" in *":\$HOME/.local/bin:"*) ;; *) export PATH="\$HOME/.local/bin:\$PATH" ;; esac
HEADER

  if [[ "$INSTALL_NODE" == "true" ]]; then
    cat <<FNM

# Node (fnm). --use-on-cd switches Node on entering a directory that carries
# .nvmrc / .node-version / package.json engines; elsewhere the fnm default applies.
# npm globals live in one prefix shared by every version (~/.npmrc).
if [ -x "$fnm_dir/fnm" ]; then
  export FNM_DIR="$fnm_dir"
  export PATH="\$FNM_DIR:\$PATH"
  eval "\$(fnm env --use-on-cd --shell $shell)"
fi
FNM
  fi

  if [[ "$shell" == "zsh" ]]; then
    render_devbox_zsh_body
  else
    render_devbox_bash_body
  fi
}

render_devbox_zsh_body() {
  if [[ "$CONFIGURE_SHELL_HISTORY" == "true" ]]; then
    cat <<ZAUTO

# Inline suggestions — BEFORE oh-my-zsh loads zsh-autosuggestions, which reads some
# of its settings only at load time. The stock fg=8 is invisible on the dark themes
# this repo configures.
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='$ZSH_AUTOSUGGEST_COLOR'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)   # fall back to completion when history has no match
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=40              # stop suggesting on very long lines (latency)
ZAUTO
  fi

  if [[ "$INSTALL_OMZ" == "true" ]]; then
    cat <<'OMZ'

# oh-my-zsh — the framework only (completion, git aliases, tab titles). Starship
# renders the prompt, so no theme. A plugins=(...) set above the loader in ~/.zshrc
# is kept; devbox's own plugins go after it — zsh-syntax-highlighting has to load
# after every other plugin — and only those actually installed, so a missing
# clone is not an omz error.
export ZSH="$HOME/.oh-my-zsh"
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  ZSH_THEME=""
  typeset -ga plugins
OMZ
    printf '  _devbox_plugins=(%s)\n' "$OMZ_PLUGINS"
    cat <<'OMZ'
  plugins=(${plugins:|_devbox_plugins})
  for _p in $_devbox_plugins; do
    [[ -d "$ZSH/plugins/$_p" || -d "${ZSH_CUSTOM:-$ZSH/custom}/plugins/$_p" ]] && plugins+=("$_p")
  done
  unset _p _devbox_plugins
  source "$ZSH/oh-my-zsh.sh"
fi
OMZ
  fi

  if [[ "$INSTALL_ZSH_PLUGINS" == "true" ]]; then
    cat <<'ZAPT'

# zsh-autosuggestions from apt, only when oh-my-zsh is not already loading it.
if (( ! ${plugins[(Ie)zsh-autosuggestions]:-0} )) \
   && [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi
ZAPT
  fi

  if [[ "$CONFIGURE_SHELL_HISTORY" == "true" ]]; then
    cat <<ZHIST

# History — AFTER oh-my-zsh, whose lib/history.zsh assigns HISTSIZE/SAVEHIST too.
HISTFILE="\$HOME/.zsh_history"
HISTSIZE=$SHELL_HISTORY_SIZE     # entries held in memory
SAVEHIST=$SHELL_HISTORY_SIZE     # entries written to disk; a smaller value truncates the file on every write
setopt EXTENDED_HISTORY          # record timestamps
setopt HIST_EXPIRE_DUPS_FIRST    # trim duplicates before unique commands
setopt HIST_IGNORE_SPACE         # a leading space keeps a command out of history
setopt HIST_FIND_NO_DUPS         # don't re-offer a duplicate while searching
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY             # append immediately and share across live shells
ZHIST
  fi

  render_devbox_fzf zsh

  if [[ "$CONFIGURE_SHELL_HISTORY" == "true" ]]; then
    cat <<'ZKEYS'

# Suggestion keys — AFTER fzf, which binds ^I (Tab) to fzf-completion when it
# loads. Mirrors PSReadLine on Windows: → accepts the whole suggestion, Ctrl+→ one
# word, Ctrl+R lists the history. Bound only when the widget exists: binding the
# Right arrow to a missing widget would break plain cursor movement.
if (( ${+widgets[autosuggest-accept]} )); then
  bindkey '^[[C' autosuggest-accept   # Right arrow: accept the whole suggestion
  bindkey '^ '   autosuggest-accept   # Ctrl+Space: accept (Right arrow is taken mid-line)
fi
bindkey '^[[1;5C' forward-word        # Ctrl+Right: accept one word of it
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
  fi

  render_devbox_eza

  cat <<'ZCWD'

# Report the cwd (OSC 7 — WezTerm uses it for tab titles and new-pane cwd) and the
# tab title (OSC 0). oh-my-zsh's termsupport already does both when it is loaded.
__devbox_term_cwd() {
  local leaf="${PWD##*/}"
  printf '\033]7;file://%s%s\033\\' "${HOST:-localhost}" "$PWD"
  printf '\033]0;%s\007' "${leaf:-/}"
}
autoload -Uz add-zsh-hook
(( ${+functions[omz_termsupport_precmd]} )) || add-zsh-hook precmd __devbox_term_cwd
ZCWD

  render_devbox_prompt_tools zsh

  if [[ "$INSTALL_ZSH_PLUGINS" == "true" ]]; then
    cat <<'ZSYH'

# zsh-syntax-highlighting from apt when oh-my-zsh is not loading it — LAST: it only
# highlights for widgets that exist by the time it loads.
if (( ! ${plugins[(Ie)zsh-syntax-highlighting]:-0} )) \
   && [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
ZSYH
  fi
}

render_devbox_bash_body() {
  if [[ "$CONFIGURE_SHELL_HISTORY" == "true" ]]; then
    cat <<BHIST

# History. Ubuntu's stock .bashrc caps it at 1000/2000 lines; these run later and win.
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
  fi

  render_devbox_fzf bash
  render_devbox_eza

  cat <<'BCWD'

# Report the cwd (OSC 7 — WezTerm uses it for tab titles and new-pane cwd) and the
# tab title (OSC 0): starship replaces PS1, dropping the OSC 0 in Ubuntu's default.
__devbox_term_cwd() {
  local leaf="${PWD##*/}"
  printf '\033]7;file://%s%s\033\\' "${HOSTNAME:-localhost}" "$PWD"
  printf '\033]0;%s\007' "${leaf:-/}"
}
case "${PROMPT_COMMAND:-}" in
  *__devbox_term_cwd*) ;;
  *) PROMPT_COMMAND="__devbox_term_cwd${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
BCWD

  render_devbox_prompt_tools bash
}

# fzf key bindings (Ctrl+T files, Ctrl+R history, Alt+C cd) and ** completion.
render_devbox_fzf() {
  local shell="$1"
  cat <<FZF

# fzf key bindings (Ctrl+T, Ctrl+R, Alt+C) and ** completion. fzf 0.48+ generates
# them (\`fzf --$shell\`); older packaged builds — Ubuntu 24.04 ships 0.44 — only
# ship example scripts, whose location has moved between releases.
if command -v fzf >/dev/null 2>&1; then
  if _devbox_fzf="\$(fzf --$shell 2>/dev/null)"; then
    eval "\$_devbox_fzf"
  else
    for _d in /usr/share/doc/fzf/examples /usr/share/fzf /usr/share/fzf/shell; do
      if [ -f "\$_d/key-bindings.$shell" ]; then
        . "\$_d/key-bindings.$shell"
        [ -f "\$_d/completion.$shell" ] && . "\$_d/completion.$shell"
        break
      fi
    done
  fi
  unset _devbox_fzf _d
fi
FZF
}

render_devbox_eza() {
  [[ "$INSTALL_EZA" == "true" ]] || return 0
  cat <<'EZA'

# ls → eza. `--icons=auto`, never a bare `--icons`: since eza 0.20 that flag takes an
# optional value, so `ls somedir` would hand "somedir" to it and fail.
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons=auto'
  alias ll='eza -la --icons=auto --git'
  alias lt='eza --tree --level=2 --icons=auto'
fi
EZA
}

# zoxide, then starship LAST: zoxide hooks in after compinit (which oh-my-zsh ran
# above), and starship's prompt must be the one left standing.
render_devbox_prompt_tools() {
  local shell="$1"
  if [[ "$INSTALL_ZOXIDE" == "true" ]]; then
    cat <<ZOX

# zoxide: z / zi, a cd that learns. After compinit, which it hooks into.
if command -v zoxide >/dev/null 2>&1; then eval "\$(zoxide init $shell)"; fi
ZOX
  fi
  if [[ "$INSTALL_STARSHIP" == "true" ]]; then
    cat <<STAR

# Starship renders the prompt — last, so no later init replaces it.
if command -v starship >/dev/null 2>&1; then eval "\$(starship init $shell)"; fi
STAR
  fi
}

# The one block devbox keeps in ~/.zshrc / ~/.bashrc.
render_devbox_loader() {
  local shell="$1"
  cat <<LOADER
# --- devbox: loader ---
# Everything devbox configures for $shell lives in ~/.config/devbox/${shell}rc, regenerated
# by setup-ubuntu.sh. Lines above this block run before it; lines below run after it.
if [ -f "\$HOME/.config/devbox/${shell}rc" ]; then . "\$HOME/.config/devbox/${shell}rc"; fi
$MANAGED_END
LOADER
}

# Rewrite the body of an existing '# --- devbox: <marker> ---' block IN PLACE.
# Returns 1 when the block is absent, so the caller decides where it goes.
set_managed_block() {
  local file="$1" marker="$2" block_file="$3" label="$4"
  local begin="# --- devbox: ${marker} ---" tmp
  grep -qxF "$begin" "$file" || return 1
  tmp="$(mktemp)"
  awk -v begin="$begin" -v endmark="$MANAGED_END" -v blockfile="$block_file" '
    $0 == begin {
      while ((getline line < blockfile) > 0) print line
      close(blockfile); inblock = 1; next
    }
    inblock && $0 == endmark { inblock = 0; next }
    inblock { next }
    { print }
  ' "$file" > "$tmp"
  if cmp -s "$tmp" "$file"; then
    echo "✓ $label already current in $(basename "$file")"
    rm -f "$tmp"
  else
    echo "→ Rewriting $label in $(basename "$file")"
    mv "$tmp" "$file"
  fi
}

# Strip from an rc file everything earlier versions of this script wrote into it —
# now generated into ~/.config/devbox — and, in ~/.zshrc, put the loader where the
# oh-my-zsh source line was, so the user's lines keep their side of it. Only exact
# lines and marked blocks devbox itself wrote are removed; everything else stays.
# The first time it changes a file it leaves <rc>.pre-devbox-config.bak.
#
# Regexes live inside the awk program, never in -v: awk processes escapes in -v
# values and turns the `\$` of `\$ZSH` into a bare `$` — an end-of-line anchor
# that matches nothing, so the migration would silently skip that line.
migrate_rc_to_devbox_config() {
  local rc="$1" shell="$2" loader tmp has_loader=0
  loader="$(mktemp)"; tmp="$(mktemp)"
  render_devbox_loader "$shell" > "$loader"
  if grep -qxF '# --- devbox: loader ---' "$rc"; then has_loader=1; fi
  awk -v shell="$shell" -v loaderfile="$loader" -v endmark="$MANAGED_END" -v has_loader="$has_loader" '
    function flush() { while (nb > 0) { print ""; nb-- } }
    function drop()  { nb = 0 }
    skip_block { if ($0 == endmark) skip_block = 0; next }
    skip_cwd   { if ($0 ~ /^esac$/ || $0 ~ /add-zsh-hook precmd __devbox_term_cwd/) skip_cwd = 0; next }
    eza_legacy && /^alias (ls|ll|lt)=/ { next }
    { eza_legacy = 0 }
    omz_legacy {   # the lines under the old "# devbox oh-my-zsh" comment
      if (/^export ZSH=/ || /^ZSH_THEME=/) next
      if (!/^plugins=\(/) omz_legacy = 0   # plugins=(...) stays: it may hold your own
    }
    /^[[:space:]]*$/ { nb++; next }
    /^# --- devbox: (fnm|eza aliases|zsh history|zsh history keys|bash history) ---$/ { drop(); skip_block = 1; next }
    $0 == "# devbox eza aliases" { drop(); eza_legacy = 1; next }
    /^# devbox terminal cwd/     { drop(); skip_cwd = 1; next }
    /^# devbox oh-my-zsh/        { drop(); omz_legacy = 1; next }
    /^eval "\$\((starship|zoxide) init (bash|zsh)\)"$/ ||
    /^eval "\$\(fzf --(bash|zsh)\)"$/ ||
    /^source \/usr\/share\/(doc\/fzf\/examples|fzf|fzf\/shell)\/(key-bindings|completion)\.(bash|zsh)$/ ||
    /^source \/usr\/share\/zsh-(autosuggestions|syntax-highlighting)\/zsh-(autosuggestions|syntax-highlighting)\.zsh$/ ||
    /^export PATH="\$HOME\/\.local\/bin:\$PATH"$/ { drop(); next }
    shell == "zsh" && /^[[:space:]]*(source|\.)[[:space:]]+"?(\$ZSH|\$\{ZSH\})"?\/oh-my-zsh\.sh/ {
      if (!placed && has_loader == 0) {
        flush(); while ((getline l < loaderfile) > 0) print l; close(loaderfile); placed = 1
      } else drop()
      next
    }
    { flush(); print }
    END { flush() }
  ' "$rc" > "$tmp"
  rm -f "$loader"
  if cmp -s "$tmp" "$rc"; then
    rm -f "$tmp"
    return
  fi
  if [[ ! -e "$rc.pre-devbox-config.bak" ]]; then
    cp "$rc" "$rc.pre-devbox-config.bak"
    echo "  (backup of the previous $(basename "$rc"): $(basename "$rc").pre-devbox-config.bak)"
  fi
  echo "→ Moved devbox-written lines out of $(basename "$rc") into ~/.config/devbox/${shell}rc"
  mv "$tmp" "$rc"
}

# Write ~/.config/devbox/<shell>rc and make sure <rc> sources it.
ensure_devbox_shell_config() {
  local shell rc gen body
  mkdir -p "$DEVBOX_RC_DIR"
  # The generated files skip what is missing rather than break the shell, so say so.
  ensure_command fzf || echo "⚠ fzf not installed — its Ctrl+R / Ctrl+T bindings will be skipped"
  body="$(mktemp)"
  for shell in bash zsh; do
    rc="$HOME/.${shell}rc"
    [[ -f "$rc" ]] || continue
    gen="$DEVBOX_RC_DIR/${shell}rc"

    render_devbox_rc "$shell" > "$body"
    if cmp -s "$body" "$gen"; then
      echo "✓ ~/.config/devbox/${shell}rc already current"
    else
      echo "→ Writing ~/.config/devbox/${shell}rc"
      cp "$body" "$gen"
    fi

    migrate_rc_to_devbox_config "$rc" "$shell"
    render_devbox_loader "$shell" > "$body"
    if ! set_managed_block "$rc" "loader" "$body" "devbox loader"; then
      echo "→ Adding the devbox loader to $(basename "$rc")"
      { printf '\n'; cat "$body"; } >> "$rc"
    fi
  done
  rm -f "$body"
}

ensure_starship() {
  # Install binary
  if ensure_command starship; then
    echo "✓ starship already installed"
  else
    echo "→ Installing starship"
    curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin"
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
  # Its init lives in ~/.config/devbox/<shell>rc (ensure_devbox_shell_config).
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

# `--render-rc bash|zsh` prints the generated ~/.config/devbox/<shell>rc and exits,
# touching nothing: audit-ubuntu.sh diffs the installed file against it.
if [[ "${1:-}" == "--render-rc" ]]; then
  render_devbox_rc "${2:?usage: setup-ubuntu.sh --render-rc bash|zsh}"
  exit
fi

# Tools this run installs into ~/.local/bin must be found by its own later checks
# (and by pipx ensurepath, which would otherwise append a PATH line to the rc files).
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

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
TOTAL_STEPS=7  # apt update, base packages, zsh, fd shim, code dir, shell config, Done
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
# Ensure .zshrc exists so ensure_devbox_shell_config can add its loader to it
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
fi

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
  if [[ "$USE_WINDOWS_GCM" == "true" ]] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    ensure_git_credential_manager
  fi
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

log "Writing shell config (~/.config/devbox) and its loader in the rc files"
ensure_devbox_shell_config

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

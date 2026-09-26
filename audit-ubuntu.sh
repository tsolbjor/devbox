#!/usr/bin/env bash
# shellcheck disable=SC2088  # report messages show ~ paths as text, never expand them
# Read-only DRIFT AUDIT for the WSL/Ubuntu side. Compares the current machine
# against what setup-ubuntu.sh / update-ubuntu.sh install and configure, and
# reports where they diverge. It changes NOTHING — every finding carries a
# two-way reconcile hint: how to fix the drift, and (for unexpected apps) how to
# adopt it into setup, so the report doubles as a setup-update worklist.
#
# "Expected" state comes straight out of setup-ubuntu.sh — the APT_PACKAGES array
# and ensure_pkg / ensure_command calls are parsed, and the generated shell config
# is rendered by `setup-ubuntu.sh --render-rc` — so this audit can never drift
# from setup itself.
#
# Not -e: the audit probes with commands that routinely exit non-zero.
set -uo pipefail

# =========================
# PARAMETERS
# =========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="${SETUP:-$SCRIPT_DIR/setup-ubuntu.sh}"

CHECK_CLIS="${CHECK_CLIS:-true}"        # expected CLIs present?
CHECK_CONFIG="${CHECK_CONFIG:-true}"    # rc blocks, starship.toml, wsl.conf, git, shell
CHECK_EXTRAS="${CHECK_EXTRAS:-true}"    # snap / pipx / npm / dotnet globals not in setup
CHECK_SERVICES="${CHECK_SERVICES:-true}" # systemd running-state + startup inventory (enabled units, crontab)
CHECK_DOCKER="${CHECK_DOCKER:-true}"    # Rancher Desktop is the intended docker engine — flag shadow apt/snap engines
CHECK_PINS="${CHECK_PINS:-true}"        # installed major versions vs the version pins in setup-ubuntu.sh
APT_EXTRAS=false                        # --apt-extras: list manual apt pkgs not in setup (noisy: includes base)
LOCAL_BIN=false                         # --local-bin: list /usr/local/bin binaries not in setup

# ensure_command names that are interop/optional, not things setup installs on Linux
CMD_DENYLIST="whoami powershell docker batcat fdfind ncu"

# Extras installed on purpose that are not part of the dev environment. Listing one
# here stops it being reported — the third answer the remove/adopt hint has no room
# for. Space-separated exact names; IGNORE_PATTERNS entries are extended regexes
# applied to every extras category. (The Windows side keeps the same idea in
# $Config.Ignore, and fills it interactively with `audit-windows.ps1 -Triage`.)
IGNORE_SNAP="${IGNORE_SNAP:-}"
IGNORE_PIPX="${IGNORE_PIPX:-}"
IGNORE_NPM="${IGNORE_NPM:-}"
IGNORE_DOTNET="${IGNORE_DOTNET:-}"
IGNORE_PATTERNS="${IGNORE_PATTERNS:-}"

# Keep in step with setup-ubuntu.sh.
FNM_DIR="${FNM_DIR:-$HOME/.local/share/fnm}"
NPM_GLOBAL_PREFIX="${NPM_GLOBAL_PREFIX:-$HOME/.local}"

for arg in "$@"; do
  case "$arg" in
    --apt-extras) APT_EXTRAS=true ;;
    --local-bin)  LOCAL_BIN=true ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

# =========================
# IMPLEMENTATION
# =========================
# Audit the fnm default Node whatever shell this was launched from: the npm
# extras check and the node pin both read it, and a non-interactive caller may
# not have sourced the rc block that puts it on PATH.
if [[ -x "$FNM_DIR/fnm" ]]; then
  export FNM_DIR PATH="$FNM_DIR:$PATH"
  eval "$("$FNM_DIR/fnm" env --shell bash)"
fi

drift=0
section() { printf '\n=== %s ===\n' "$1"; }
report_ok()   { printf '✓ %s\n' "$1"; }
report_warn() { printf '⚠ %s\n' "$1"; }
report_info() { printf '· %s\n' "$1"; }   # inventory line — visibility only, never counted as drift
report_drift() {
  drift=$((drift + 1))
  printf '⚠ %s\n' "$1"; shift
  for line in "$@"; do printf '    %s\n' "$line"; done
}

[[ -f "$SETUP" ]] || { echo "setup script not found: $SETUP" >&2; exit 1; }

echo "devbox drift audit (Ubuntu/WSL)"
echo "Comparing this machine against $(basename "$SETUP") + update-ubuntu.sh"

# ---- parse expected sets ----
mapfile -t EXPECTED_APT < <(
  { sed -n '/APT_PACKAGES=(/,/^)/p' "$SETUP" | grep -oE '^[[:space:]]+[a-z0-9][a-z0-9._+-]*' | tr -d '[:space:]'
    grep -oE 'ensure_pkg [a-z0-9._+-]+' "$SETUP" | awk '{print $2}'
  } | sort -u
)

mapfile -t EXPECTED_CMDS < <(
  grep -oE 'ensure_command [a-z0-9_-]+' "$SETUP" | awk '{print $2}' | sort -u \
    | grep -vwE "$(echo "$CMD_DENYLIST" | tr ' ' '|')"
)

# binaries setup drops into /usr/local/bin (two tar patterns: plain and strip-components)
mapfile -t EXPECTED_LOCALBIN < <(
  { grep -oE '\-C /usr/local/bin [a-z0-9-]+' "$SETUP" | awk '{print $3}'
    grep -oE '/usr/local/bin "[a-z0-9-]+/[a-z0-9-]+"' "$SETUP" | sed -E 's|.*/([a-z0-9-]+)"$|\1|'
  } | sort -u
)

in_list() { local needle="$1"; shift; local x; for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done; return 1; }

ignored=0
# Silenced by one of the IGNORE_* lists (exact) or IGNORE_PATTERNS (ERE)? Both
# lists are deliberately unquoted below — they are space-separated by contract.
is_ignored() {
  local name="$1" list="$2" x
  for x in $list;            do [[ "$x" == "$name" ]] && return 0; done
  for x in $IGNORE_PATTERNS; do grep -qE "$x" <<< "$name" && return 0; done
  return 1
}
# Count and skip: `is_ignored ... && skip_ignored && continue` reads left to right.
skip_ignored() { ignored=$((ignored + 1)); return 0; }

# ---------- expected CLIs present ----------
if [[ "$CHECK_CLIS" == "true" ]]; then
  section "CLIs"
  missing=0
  for cmd in "${EXPECTED_CMDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      report_drift "Missing CLI: $cmd" "fix: bash setup-ubuntu.sh"
      missing=$((missing + 1))
    fi
  done
  [[ $missing -eq 0 ]] && report_ok "All ${#EXPECTED_CMDS[@]} expected CLIs present."
fi

# ---------- config drift ----------
if [[ "$CHECK_CONFIG" == "true" ]]; then
  section "Managed config"

  # Shell config. Setup generates ~/.config/devbox/<shell>rc whole and leaves a
  # single loader block in each rc file (ensure_devbox_shell_config). So: the
  # generated file must match what setup would write now, the loader must be there
  # exactly once, and nothing an older setup wrote straight into the rc file may be
  # left behind — it would run a second time, in whatever order it happens to sit.
  #
  # Lines those older setups wrote. The same set migrate_rc_to_devbox_config removes.
  legacy_rc_re='^# --- devbox: (fnm|eza aliases|zsh history|zsh history keys|bash history) ---$'
  legacy_rc_re+='|^# devbox (eza aliases|terminal cwd|oh-my-zsh)'
  legacy_rc_re+='|^eval "\$\((starship|zoxide) init (bash|zsh)\)"$|^eval "\$\(fzf --(bash|zsh)\)"$'
  legacy_rc_re+='|^source /usr/share/(doc/fzf/examples|fzf|fzf/shell)/(key-bindings|completion)\.(bash|zsh)$'
  legacy_rc_re+='|^source /usr/share/zsh-(autosuggestions|syntax-highlighting)/'
  # The generated zshrc loads oh-my-zsh itself; a second source line loads it twice.
  omz_source_re='^[[:space:]]*(source|\.)[[:space:]]+"?(\$ZSH|\$\{ZSH\})"?/oh-my-zsh\.sh'

  for shell in bash zsh; do
    rc="$HOME/.${shell}rc"; gen="$HOME/.config/devbox/${shell}rc"
    if [[ "$shell" == "zsh" ]] && ! command -v zsh >/dev/null 2>&1; then continue; fi
    if [[ ! -f "$rc" ]]; then
      report_drift "~/.${shell}rc missing entirely." "fix: bash setup-ubuntu.sh"
      continue
    fi
    # grep -c prints 0 itself on no match; `|| true` only absorbs its exit status.
    n=$(grep -cxF '# --- devbox: loader ---' "$rc" || true)
    if [[ "$n" -eq 0 ]]; then
      report_drift "~/.${shell}rc does not load ~/.config/devbox/${shell}rc (devbox loader block missing)." \
        "fix: bash setup-ubuntu.sh"
    elif [[ "$n" -gt 1 ]]; then
      report_drift "~/.${shell}rc has the devbox loader $n times — everything devbox configures runs $n times." \
        "fix: delete all but one '# --- devbox: loader ---' block"
    fi
    if [[ ! -f "$gen" ]]; then
      report_drift "~/.config/devbox/${shell}rc missing." "fix: bash setup-ubuntu.sh"
    elif ! cmp -s <(bash "$SETUP" --render-rc "$shell" 2>/dev/null) "$gen"; then
      report_drift "~/.config/devbox/${shell}rc differs from what setup-ubuntu.sh generates (edited, or setup changed since)." \
        "see:  diff <(bash setup-ubuntu.sh --render-rc $shell) ~/.config/devbox/${shell}rc" \
        "fix:  bash setup-ubuntu.sh — it rewrites the file, so move anything of yours into ~/.${shell}rc first"
    fi
    leftovers=$(grep -nE "$legacy_rc_re" "$rc" | cut -d: -f1 | paste -sd, - || true)
    if [[ -n "$leftovers" ]]; then
      report_drift "~/.${shell}rc still carries lines devbox now generates (line $leftovers) — they run twice." \
        "fix: bash setup-ubuntu.sh (moves them out, keeping ~/.${shell}rc.pre-devbox-config.bak)"
    fi
    if [[ "$shell" == "zsh" ]]; then
      omz_lines=$(grep -nE "$omz_source_re" "$rc" | cut -d: -f1 | paste -sd, - || true)
      if [[ -n "$omz_lines" ]]; then
        report_drift "~/.zshrc sources oh-my-zsh itself (line $omz_lines); the devbox zshrc loads it too, so it loads twice." \
          "fix: bash setup-ubuntu.sh (puts the devbox loader in its place)"
      fi
    fi
  done

  # Effective values, from a real interactive zsh: whatever ~/.zshrc does after the
  # loader wins, and only a started shell shows the end result. DISABLE_AUTO_UPDATE
  # and </dev/null keep oh-my-zsh's update prompt from waiting on an answer.
  want_hist=$(grep -m1 '^SHELL_HISTORY_SIZE=' "$SETUP" 2>/dev/null | grep -oE '[0-9]+' | head -1)
  want_omz=$(grep -m1 '^INSTALL_OMZ=' "$SETUP" 2>/dev/null | grep -oE 'true|false' | head -1 || true)
  if command -v zsh >/dev/null 2>&1 && [[ -f "$HOME/.zshrc" ]]; then
    probe=$(DISABLE_AUTO_UPDATE=true timeout 30 zsh -ic \
      'print -r -- "DEVBOX_PROBE|$HISTSIZE|$SAVEHIST|${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE-}|$+functions[omz]"' \
      </dev/null 2>/dev/null | grep '^DEVBOX_PROBE|' | tail -1)
    if [[ -z "$probe" ]]; then
      report_warn "Could not start an interactive zsh to read its effective settings."
    else
      IFS='|' read -r _ have_hist have_save style omz_loaded <<< "$probe"
      if [[ -n "$want_hist" ]]; then
        for pair in "HISTSIZE:$have_hist" "SAVEHIST:$have_save"; do
          var=${pair%%:*}; have=${pair#*:}
          if [[ -z "$have" || "$have" -lt "$want_hist" ]]; then
            report_drift "zsh ends up with $var=${have:-unset}, below the expected $want_hist — history is being truncated." \
              "fix: remove the later $var= from ~/.zshrc, or adopt it by setting SHELL_HISTORY_SIZE in setup-ubuntu.sh"
          fi
        done
      fi
      case "$style" in
        ''|fg=8|fg=black|fg=0)
          report_drift "zsh ends up with ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='${style}' — suggestions are invisible on dark themes." \
            "fix: bash setup-ubuntu.sh, or remove the later override from ~/.zshrc" ;;
        *) report_ok "Inline suggestion colour set ($style)." ;;
      esac
      if [[ "$want_omz" == "true" && -d "$HOME/.oh-my-zsh" && "$omz_loaded" != "1" ]]; then
        report_drift "oh-my-zsh is installed but an interactive zsh does not load it." "fix: bash setup-ubuntu.sh"
      fi
    fi
  fi
  if [[ "$want_omz" == "true" && ! -d "$HOME/.oh-my-zsh" ]] && command -v zsh >/dev/null 2>&1; then
    report_drift "oh-my-zsh missing (setup installs it)." "fix: bash setup-ubuntu.sh"
  fi

  # starship.toml (setup never overwrites it, but it should exist)
  if [[ -f "$HOME/.config/starship.toml" ]]; then
    report_ok "starship.toml present."
  else
    report_drift "~/.config/starship.toml missing." "fix: bash setup-ubuntu.sh"
  fi

  # /etc/wsl.conf
  if [[ -f /etc/wsl.conf ]]; then
    grep -qE 'options[[:space:]]*=[[:space:]]*metadata' /etc/wsl.conf \
      || report_drift "/etc/wsl.conf missing 'options = metadata'." "fix: bash setup-ubuntu.sh"
    grep -qE 'systemd[[:space:]]*=[[:space:]]*true' /etc/wsl.conf \
      || report_warn "/etc/wsl.conf has no 'systemd = true' (expected unless WSL_ENABLE_SYSTEMD=false)."
  else
    report_drift "/etc/wsl.conf missing." "fix: bash setup-ubuntu.sh"
  fi

  # default shell = zsh
  login_shell=$(getent passwd "$USER" | cut -d: -f7)
  if [[ "$login_shell" == *zsh ]]; then
    report_ok "Default shell is zsh."
  else
    report_drift "Default shell is '$login_shell', not zsh." "fix: chsh -s \"\$(command -v zsh)\""
  fi

  # git global config keys setup manages
  if command -v git >/dev/null 2>&1; then
    for key in user.name user.email init.defaultBranch pull.rebase push.autoSetupRemote core.pager; do
      if [[ -z "$(git config --global --get "$key" 2>/dev/null)" ]]; then
        report_drift "git config --global $key is unset." "fix: bash setup-ubuntu.sh"
      fi
    done
    # HTTPS auth via the Windows Git Credential Manager (ensure_git_credential_manager),
    # checked only where setup would have wired it: on WSL, with Git for Windows present.
    gcm="/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"
    if grep -q '^USE_WINDOWS_GCM="${USE_WINDOWS_GCM:-true}"' "$SETUP" && [[ -x "$gcm" ]]; then
      helper=$(git config --global --get credential.helper 2>/dev/null)
      if [[ "$helper" != "${gcm// /\\ }" ]]; then
        report_drift "git credential.helper is '${helper:-unset}', not the Windows Git Credential Manager." \
          "fix: bash setup-ubuntu.sh" "keep: set USE_WINDOWS_GCM=false in setup-ubuntu.sh"
      fi
    fi
  fi
fi

# ---------- extras (snap / pipx / npm) ----------
if [[ "$CHECK_EXTRAS" == "true" ]]; then
  section "Extra apps (not in setup)"

  # snap — ignore the base snaps every install carries
  if command -v snap >/dev/null 2>&1; then
    snap_base='^(core|core[0-9]+|snapd|bare|gtk-common-themes|gnome-.*|mesa-.*|snapd-desktop-integration)$'
    while read -r sn _; do
      [[ -z "$sn" || "$sn" == "Name" ]] && continue
      echo "$sn" | grep -qE "$snap_base" && continue
      is_ignored "$sn" "$IGNORE_SNAP" && skip_ignored && continue
      report_drift "Extra snap: $sn" "remove: sudo snap remove $sn" "adopt: add a 'snap install $sn' step to setup-ubuntu.sh"
    done < <(snap list 2>/dev/null)
  fi

  # pipx tools vs expected (pipx install <name>)
  if command -v pipx >/dev/null 2>&1; then
    mapfile -t EXPECTED_PIPX < <(grep -oE 'pipx install [a-z0-9._-]+' "$SETUP" | awk '{print $3}' | sort -u)
    while read -r pkg; do
      [[ -z "$pkg" ]] && continue
      is_ignored "$pkg" "$IGNORE_PIPX" && skip_ignored && continue
      in_list "$pkg" "${EXPECTED_PIPX[@]:-}" || \
        report_drift "Extra pipx tool: $pkg" "remove: pipx uninstall $pkg" "adopt: add 'pipx install $pkg' to setup-ubuntu.sh"
    done < <(pipx list --short 2>/dev/null | awk '{print $1}')
  fi

  # npm globals vs expected (npm install -g <name>)
  if command -v npm >/dev/null 2>&1; then
    mapfile -t EXPECTED_NPM < <(grep -oE 'npm install -g [@a-z0-9._/-]+' "$SETUP" update-ubuntu.sh 2>/dev/null | awk '{print $4}' | sort -u)
    while read -r pkg; do
      # npm and corepack ship bundled with Node — not "extra" installs
      [[ -z "$pkg" || "$pkg" == "npm" || "$pkg" == "corepack" ]] && continue
      is_ignored "$pkg" "$IGNORE_NPM" && skip_ignored && continue
      in_list "$pkg" "${EXPECTED_NPM[@]:-}" || \
        report_drift "Extra npm global: $pkg" "remove: npm uninstall -g $pkg" "adopt: add 'npm install -g $pkg' to setup-ubuntu.sh"
    done < <(npm ls -g --depth=0 --parseable 2>/dev/null | sed '1d' | sed -E 's|.*/node_modules/||')
  fi

  # .NET global tools vs expected (dotnet tool install -g <name>). `dotnet tool
  # list -g` prints a header row plus a dashed rule before the data, hence +3.
  if command -v dotnet >/dev/null 2>&1; then
    mapfile -t EXPECTED_DOTNET < <(grep -ohE 'dotnet tool install -g [a-zA-Z0-9._-]+' "$SETUP" update-ubuntu.sh 2>/dev/null | awk '{print $5}' | sort -u)
    while read -r pkg; do
      [[ -z "$pkg" ]] && continue
      is_ignored "$pkg" "$IGNORE_DOTNET" && skip_ignored && continue
      in_list "$pkg" "${EXPECTED_DOTNET[@]:-}" || \
        report_drift "Extra .NET global tool: $pkg" "remove: dotnet tool uninstall -g $pkg" "adopt: add 'dotnet tool install -g $pkg' to ensure_dotnet_tools in setup-ubuntu.sh"
    done < <(dotnet tool list -g 2>/dev/null | tail -n +3 | awk '{print $1}')
  fi
fi

# ---------- startup & services ----------
if [[ "$CHECK_SERVICES" == "true" ]]; then
  section "Startup & services"

  if command -v systemctl >/dev/null 2>&1; then
    # systemd expected up when WSL_ENABLE_SYSTEMD (default). is-system-running prints
    # 'running'/'degraded' when the manager is PID 1, or errors when it is not.
    state=$(systemctl is-system-running 2>/dev/null || true)
    case "$state" in
      running)  report_ok "systemd is running." ;;
      degraded) report_warn "systemd running but degraded — 'systemctl --failed' to inspect." ;;
      "")       report_warn "systemd not managing this session (WSL_ENABLE_SYSTEMD=false?)." ;;
      *)        report_warn "systemd state: $state." ;;
    esac

    # Inventory (informational — not counted as drift): units enabled AGAINST their
    # vendor preset, i.e. someone turned them on by hand. Baseline enabled-by-preset
    # units are skipped so the list stays high-signal.
    echo "  startup inventory (informational — review, adopt into setup, or disable):"
    while read -r unit unit_state preset _; do
      [[ -z "$unit" ]] && continue
      # newer systemd prints a PRESET column; flag enabled-but-preset-disabled
      if [[ "$unit_state" == "enabled" && "$preset" == "disabled" ]]; then
        report_info "manually enabled unit: $unit"
      fi
    done < <(systemctl list-unit-files --type=service --state=enabled --no-legend --no-pager 2>/dev/null)

    # user-scoped systemd units enabled against preset (baseline sockets skipped)
    while read -r unit unit_state preset _; do
      [[ -z "$unit" ]] && continue
      if [[ "$unit_state" == "enabled" && "$preset" == "disabled" ]]; then
        report_info "user unit manually enabled: $unit"
      fi
    done < <(systemctl --user list-unit-files --state=enabled --no-legend --no-pager 2>/dev/null)
  else
    report_warn "systemctl not available — skipping service checks."
  fi

  # user crontab (high-signal; usually empty)
  if command -v crontab >/dev/null 2>&1; then
    while read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      report_info "crontab: $line"
    done < <(crontab -l 2>/dev/null)
  fi
fi

# ---------- docker engine ----------
# setup-ubuntu.sh installs NO docker on the Linux side — Rancher Desktop (moby)
# injects the CLI + socket via its WSL integration. A rival apt docker-ce or snap
# docker ships its own dockerd that grabs /var/run/docker.sock ahead of Rancher,
# so the shell silently talks to the wrong engine. The generic services check
# misses this: those daemons sit at preset=enabled, and it never inspects which
# engine owns the socket. This section does.
if [[ "$CHECK_DOCKER" == "true" ]]; then
  section "Docker engine (Rancher Desktop)"

  # Shadow engines — any of these is drift that fights Rancher for the socket.
  shadow=0
  if command -v dpkg-query >/dev/null 2>&1; then
    while read -r pkg; do
      [[ -z "$pkg" ]] && continue
      shadow=1
      report_drift "Shadow apt docker package: $pkg" \
        "remove: sudo apt-get purge -y $pkg && sudo apt-get autoremove -y" \
        "why: Rancher Desktop provides docker in WSL; apt docker-ce runs a rival dockerd"
    done < <(dpkg-query -W -f='${Package}\n' docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras 2>/dev/null)
  fi
  if command -v snap >/dev/null 2>&1 && snap list docker >/dev/null 2>&1; then
    shadow=1
    report_drift "Shadow snap docker installed" \
      "remove: sudo snap remove docker" \
      "why: snap dockerd grabs /var/run/docker.sock ahead of Rancher Desktop"
  fi
  [[ "$shadow" == "0" ]] && report_ok "No shadow docker engines (apt/snap)."

  # CLI wired to Rancher, and which daemon actually answers?
  if command -v docker >/dev/null 2>&1; then
    docker_path=$(command -v docker)
    case "$docker_path" in
      *[Rr]ancher*) report_ok "docker CLI is Rancher's ($docker_path)." ;;
      *) report_drift "docker CLI is not Rancher's: $docker_path" \
           "fix: remove shadow docker (above), then re-toggle Rancher Desktop → WSL Integrations" \
           "expect: a path under Rancher Desktop resources or /mnt/wsl/rancher-desktop/bin" ;;
    esac

    os=$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || true)
    case "$os" in
      *"Rancher Desktop"*) report_ok "docker daemon is Rancher Desktop ($os)." ;;
      "") report_warn "docker daemon not reachable — start Rancher Desktop (moby engine)." ;;
      *)  report_drift "docker daemon is not Rancher: $os" \
            "fix: stop/remove the rival dockerd, then re-toggle Rancher Desktop → WSL Integrations" \
            "expect: OperatingSystem = 'Rancher Desktop WSL Distribution'" ;;
    esac
  else
    report_warn "docker CLI not found — enable Rancher Desktop → WSL Integrations for this distro."
  fi
fi

# ---------- opt-in noisy checks ----------
if [[ "$LOCAL_BIN" == "true" ]]; then
  section "/usr/local/bin binaries not in setup"
  for bin in /usr/local/bin/*; do
    [[ -f "$bin" || -L "$bin" ]] || continue
    name=$(basename "$bin")
    # expected if setup drops it here, or if it's any CLI setup otherwise manages
    in_list "$name" "${EXPECTED_LOCALBIN[@]:-}" && continue
    in_list "$name" "${EXPECTED_CMDS[@]:-}" && continue
    report_drift "Extra binary: /usr/local/bin/$name" "remove: sudo rm /usr/local/bin/$name" "adopt: add an ensure_* installer to setup-ubuntu.sh"
  done
fi

if [[ "$APT_EXTRAS" == "true" ]]; then
  section "Manually apt-installed, not in setup (includes base system — review)"
  comm -23 <(apt-mark showmanual 2>/dev/null | sort) <(printf '%s\n' "${EXPECTED_APT[@]}" | sort) \
    | while read -r pkg; do
        [[ -z "$pkg" ]] && continue
        report_drift "Manual apt package: $pkg" "remove: sudo apt remove $pkg" "adopt: add '$pkg' to APT_PACKAGES in setup-ubuntu.sh"
      done
fi

# ---------- version pins ----------
# The three pins in setup-ubuntu.sh track upstream support windows, but every
# ensure_* that uses them short-circuits on "command already present" — so bumping
# a pin provisions a NEW machine correctly and silently does nothing to this one.
# Nothing else would ever tell you, hence this section. Read-only, like the rest:
# `update-ubuntu.sh --pins` is what actually performs the upgrade.
if [[ "$CHECK_PINS" == "true" ]]; then
  section "Version pins"

  # Parsed from setup-ubuntu.sh so the pin lives in exactly one place.
  setup_pin() { grep -m1 "^${1}=" "$SETUP" | sed -e 's/^[^:]*:-//' -e 's/}.*//'; }

  pin_drift() {  # label, want, have, extra-hint
    report_drift "$1: pinned $2, installed $3" \
      "fix:  bash update-ubuntu.sh --pins" \
      "keep: change the pin in setup-ubuntu.sh${4:+ ($4)}"
  }

  want_dotnet=$(setup_pin DOTNET_SDK_VERSION)
  if [[ -n "$want_dotnet" ]] && command -v dotnet >/dev/null 2>&1; then
    if dotnet --list-sdks 2>/dev/null | grep -q "^${want_dotnet}\."; then
      report_ok "dotnet SDK ${want_dotnet}.x installed."
    else
      have=$(dotnet --list-sdks 2>/dev/null | awk '{print $1}' | paste -sd, - )
      report_drift "dotnet SDK: pinned ${want_dotnet}.x, installed ${have:-none}" \
        "fix:  bash setup-ubuntu.sh   (adds it alongside; SDKs coexist, nothing is removed)" \
        "keep: change DOTNET_SDK_VERSION in setup-ubuntu.sh"
    fi
  fi

  want_kubectl=$(setup_pin KUBECTL_VERSION)
  if [[ -n "$want_kubectl" ]] && command -v kubectl >/dev/null 2>&1; then
    have=$(kubectl version --client 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+' | head -1)
    [[ "$have" == "$want_kubectl" ]] \
      && report_ok "kubectl ${want_kubectl} installed." \
      || pin_drift "kubectl" "$want_kubectl" "${have:-unknown}"
    # The apt source pins the minor the repo serves; upgrading the binary without
    # it just reinstalls the old one on the next apt upgrade.
    repo=$(grep -oE 'stable:/v[0-9]+\.[0-9]+' /etc/apt/sources.list.d/kubernetes.list 2>/dev/null | head -1 | sed 's|stable:/||')
    if [[ -n "$repo" && "$repo" != "$want_kubectl" ]]; then
      report_drift "kubectl apt repo still serves $repo (pin is $want_kubectl)" \
        "fix: bash update-ubuntu.sh --pins"
    fi
  fi

  want_node=$(setup_pin NODE_MAJOR_VERSION)
  if [[ -n "$want_node" ]]; then
    if [[ -x "$FNM_DIR/fnm" ]]; then
      node_default=""
      link=$(readlink "$FNM_DIR/aliases/default" 2>/dev/null) && node_default=$(basename "$(dirname "$link")")
      have=${node_default#v}; have=${have%%.*}
      [[ "$have" == "$want_node" ]] \
        && report_ok "node ${want_node}.x is the fnm default ($node_default)." \
        || pin_drift "node (fnm default)" "${want_node}.x" "${node_default:-unset}"
    elif grep -q '^INSTALL_NODE="${INSTALL_NODE:-true}"' "$SETUP"; then
      report_drift "fnm not installed — setup provides Node through it" "fix: bash setup-ubuntu.sh"
    fi
  fi
fi

# ---------- node toolchain ----------
# Setup provides Node through fnm, with npm globals in one prefix shared by every
# Node version. Anything else providing node — the apt package, NodeSource, nvm, a
# root-owned global prefix from before — is either shadowed by fnm or shadowing it,
# and never updated either way. The `node` that wins PATH can look fine while an
# off-pin copy sits behind it, reachable as `nodejs`, /usr/bin/node, or from any
# shell that skipped the rc block, so each is checked on its own.
if [[ "$CHECK_CONFIG" == "true" && -x "$FNM_DIR/fnm" ]]; then
  section "Node toolchain (fnm)"
  node_clean=true

  apt_node=$(dpkg-query -W -f='${db:Status-Status} ${Version}' nodejs 2>/dev/null || true)
  if [[ "$apt_node" == installed\ * ]]; then
    node_clean=false
    report_drift "apt nodejs ${apt_node#installed } installed alongside fnm" \
"fix: bash setup-ubuntu.sh   (offers to migrate it; MIGRATE_LEGACY_NODE=yes to skip the prompt)" \
      "or:  sudo apt-get purge nodejs npm && sudo apt-get autoremove"
  fi
  if [[ -f /etc/apt/sources.list.d/nodesource.list ]]; then
    node_clean=false
    report_drift "NodeSource apt repo still configured" \
"fix: bash setup-ubuntu.sh   (offers to migrate it; MIGRATE_LEGACY_NODE=yes to skip the prompt)" \
      "or:  sudo rm /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg"
  fi
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc" ]] && grep -q 'NVM_DIR' "$rc"; then
      node_clean=false
      report_drift "$(basename "$rc") still loads nvm (slows startup; fnm supersedes it)" \
"fix: bash setup-ubuntu.sh   (offers to migrate it; MIGRATE_LEGACY_NODE=yes to skip the prompt)" \
        "or:  remove the NVM_DIR lines from $rc, then rm -rf ~/.nvm"
    fi
  done
  for dir in /usr/local/lib/node_modules /usr/lib/node_modules; do
    [[ "$dir" == "$NPM_GLOBAL_PREFIX/lib/node_modules" ]] && continue
    leftovers=$(find "$dir" -mindepth 1 -maxdepth 1 ! -name npm ! -name corepack -printf '%f ' 2>/dev/null)
    if [[ -n "$leftovers" ]]; then
      node_clean=false
      report_drift "npm globals left in old root-owned prefix $dir: $leftovers" \
"fix: bash setup-ubuntu.sh   (offers to reinstall them under fnm and remove these; MIGRATE_LEGACY_NODE=yes to skip the prompt)" \
        "or:  sudo rm -rf $dir/<pkg> plus its link in ${dir%/lib/node_modules}/bin"
    fi
  done
  if command -v npm >/dev/null 2>&1; then
    npm_prefix=$(npm prefix -g 2>/dev/null)
    if [[ "$npm_prefix" != "$NPM_GLOBAL_PREFIX" ]]; then
      node_clean=false
      report_drift "npm global prefix is ${npm_prefix:-unset} (expected $NPM_GLOBAL_PREFIX — globals would be per Node version)" \
        "fix: bash setup-ubuntu.sh"
    fi
  fi

  # Several node installs on PATH — the winner depends on rc load order, and
  # `nodejs` / non-interactive shells may get a different one. Windows copies under
  # /mnt/ arrive via interop PATH and are ignored; usrmerge makes /bin and /usr/bin
  # one directory, so dedupe on the resolved path.
  node_paths=$(type -ap node 2>/dev/null | grep -v '^/mnt/' | while read -r p; do readlink -f "$p"; done | awk '!seen[$0]++' || true)
  if [[ $(grep -c . <<<"$node_paths") -gt 1 ]]; then
    node_clean=false
    report_warn "multiple node installs on PATH (first wins): $(paste -sd' ' <<<"$node_paths")"
  fi

  [[ "$node_clean" == "true" ]] && report_ok "fnm is the only Node provider; npm globals in $NPM_GLOBAL_PREFIX."
fi

# ---------- summary ----------
echo
if [[ $drift -eq 0 ]]; then
  echo "No drift detected — machine matches setup."
else
  echo "$drift drift item(s) found. Each lists a fix and (for extras) how to adopt it into setup."
  echo "Tip: rerun with --apt-extras / --local-bin for the noisier checks."
fi
if [[ $ignored -gt 0 ]]; then
  echo "$ignored extra(s) silenced by the IGNORE_* lists at the top of this script."
fi

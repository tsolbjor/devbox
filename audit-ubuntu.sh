#!/usr/bin/env bash
# Read-only DRIFT AUDIT for the WSL/Ubuntu side. Compares the current machine
# against what setup-ubuntu.sh / update-ubuntu.sh install and configure, and
# reports where they diverge. It changes NOTHING — every finding carries a
# two-way reconcile hint: how to fix the drift, and (for unexpected apps) how to
# adopt it into setup, so the report doubles as a setup-update worklist.
#
# "Expected" state is parsed straight out of setup-ubuntu.sh (the APT_PACKAGES
# array, ensure_pkg / ensure_command calls, rc markers) so this audit can never
# drift from setup itself.
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
CHECK_EXTRAS="${CHECK_EXTRAS:-true}"    # snap / pipx / npm globals not in setup
CHECK_SERVICES="${CHECK_SERVICES:-true}" # systemd running-state + startup inventory (enabled units, crontab)
CHECK_DOCKER="${CHECK_DOCKER:-true}"    # Rancher Desktop is the intended docker engine — flag shadow apt/snap engines
APT_EXTRAS=false                        # --apt-extras: list manual apt pkgs not in setup (noisy: includes base)
LOCAL_BIN=false                         # --local-bin: list /usr/local/bin binaries not in setup

# ensure_command names that are interop/optional, not things setup installs on Linux
CMD_DENYLIST="whoami powershell docker batcat fdfind ncu"

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

  check_rc_marker() {  # file, grep-pattern, human label — flags missing AND duplicated
    local file="$1" pat="$2" label="$3"
    [[ -f "$file" ]] || { report_drift "$(basename "$file") missing entirely." "fix: bash setup-ubuntu.sh"; return; }
    # grep -c already prints 0 on no match (and exits 1); the old `|| echo 0` here
    # appended a second 0, and the resulting "0\n0" made every [[ -eq ]] below an
    # error — so the missing-block branch never fired for any marker.
    local n; n=$(grep -cE "$pat" "$file" 2>/dev/null); n=${n:-0}
    if [[ "$n" -eq 0 ]]; then
      report_drift "$(basename "$file"): $label block missing." "fix: bash setup-ubuntu.sh (re-appends managed blocks)"
    elif [[ "$n" -gt 1 ]]; then
      report_drift "$(basename "$file"): $label appears $n times (duplicated)." "fix: edit $file and remove the duplicate"
    fi
  }

  check_rc_present() {  # file, grep-pattern, human label — flags missing only (multi-line blocks are normal)
    local file="$1" pat="$2" label="$3"
    [[ -f "$file" ]] || { report_drift "$(basename "$file") missing entirely." "fix: bash setup-ubuntu.sh"; return; }
    grep -qE "$pat" "$file" 2>/dev/null \
      || report_drift "$(basename "$file"): $label missing." "fix: bash setup-ubuntu.sh (re-appends managed blocks)"
  }

  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    check_rc_marker  "$rc" 'starship init'      'starship init'
    check_rc_marker  "$rc" 'zoxide init'        'zoxide init'
    check_rc_marker  "$rc" 'devbox eza aliases' 'eza aliases'
    check_rc_marker  "$rc" 'devbox terminal cwd' 'terminal cwd/title reporting'
    check_rc_present "$rc" 'fzf'                 'fzf integration'
  done
  check_rc_marker "$HOME/.bashrc" 'devbox: bash history ---'     'bash history settings'
  check_rc_marker "$HOME/.zshrc"  'devbox: zsh history ---'      'zsh history settings'
  check_rc_marker "$HOME/.zshrc"  'devbox: zsh history keys ---' 'zsh history keybindings'

  # The two zsh history blocks are load-order sensitive, and being present in the
  # wrong place fails silently: omz reassigns HISTSIZE/SAVEHIST over anything above
  # it, and fzf's integration rebinds ^I over anything above it. Compare line
  # numbers rather than trusting marker presence.
  if [[ -f "$HOME/.zshrc" ]]; then
    line_of() { grep -nF -m1 -- "$1" "$HOME/.zshrc" 2>/dev/null | cut -d: -f1; }
    hist_ln=$(line_of '# --- devbox: zsh history ---')
    keys_ln=$(line_of '# --- devbox: zsh history keys ---')
    # Match the real source line, not the managed block's own comment, which quotes
    # this exact path as documentation and would otherwise always win the -m1.
    omz_ln=$(grep -nE '^[[:space:]]*(source|\.)[[:space:]]+\$ZSH/oh-my-zsh\.sh' "$HOME/.zshrc" 2>/dev/null | head -1 | cut -d: -f1)
    # Last line that *loads* fzf, not merely mentions it: key-bindings.zsh and
    # completion.zsh are sourced separately, and the keys block below references
    # fzf-completion / FZF_CTRL_R_OPTS by name without loading anything.
    fzf_ln=$(grep -nE '^[[:space:]]*(source|eval|\.)[^#]*fzf' "$HOME/.zshrc" 2>/dev/null | tail -1 | cut -d: -f1)

    if [[ -n "$hist_ln" && -n "$omz_ln" && "$hist_ln" -gt "$omz_ln" ]]; then
      report_drift "zsh history block (line $hist_ln) sits below the oh-my-zsh source line (line $omz_ln)." \
        "omz's lib/history.zsh reassigns HISTSIZE/SAVEHIST, so the block has no effect." \
        "fix: move the '# --- devbox: zsh history ---' block above the oh-my-zsh source line"
    fi
    if [[ -n "$keys_ln" && -n "$fzf_ln" && "$keys_ln" -lt "$fzf_ln" ]]; then
      report_drift "zsh history keybindings (line $keys_ln) sit above the fzf integration (line $fzf_ln)." \
        "fzf binds ^I to fzf-completion when it loads, clobbering the Tab widget." \
        "fix: move the '# --- devbox: zsh history keys ---' block to the end of ~/.zshrc"
    fi

    # Effective values, not just marker presence — a later HISTSIZE=… anywhere in
    # the file (or a stale block from an older setup) silently wins.
    want_hist=$(grep -m1 '^SHELL_HISTORY_SIZE=' "$SETUP" 2>/dev/null | grep -oE '[0-9]+' | head -1)
    if [[ -n "$want_hist" ]]; then
      for var in HISTSIZE SAVEHIST; do
        have=$(grep -oE "^${var}=[0-9]+" "$HOME/.zshrc" 2>/dev/null | tail -1 | cut -d= -f2)
        if [[ -z "$have" ]]; then
          report_drift ".zshrc sets no $var (zsh defaults to 1000; omz to 10000)." "fix: bash setup-ubuntu.sh"
        elif [[ "$have" -lt "$want_hist" ]]; then
          report_drift ".zshrc $var=$have, below the expected $want_hist — history is being truncated." \
            "fix: bash setup-ubuntu.sh, or adopt the smaller value by setting SHELL_HISTORY_SIZE in setup-ubuntu.sh"
        fi
      done
    fi

    # zsh-autosuggestions' stock fg=8 renders as invisible ghost text on the dark
    # terminal themes this repo configures — the suggestion is there, unreadable.
    style=$(grep -m1 '^ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE=' "$HOME/.zshrc" 2>/dev/null | cut -d= -f2- | tr -d "'\"")
    case "$style" in
      '')        report_drift "ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE unset — suggestions render in fg=8 (invisible on dark themes)." \
                   "fix: bash setup-ubuntu.sh" ;;
      fg=8|fg=black|fg=0)
                 report_drift "ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='$style' is the invisible default." \
                   "fix: bash setup-ubuntu.sh, or set ZSH_AUTOSUGGEST_COLOR to a readable value" ;;
      *)         report_ok "Inline suggestion colour set ($style)." ;;
    esac
  fi
  # Each zsh-users plugin must be loaded exactly once — as an oh-my-zsh plugin
  # (custom/plugins clone) or sourced from the apt copy, never both.
  for zp in zsh-autosuggestions zsh-syntax-highlighting; do
    via_omz=false; via_apt=false
    grep -qE "^plugins=\(.*${zp}" "$HOME/.zshrc" 2>/dev/null && via_omz=true
    # -F: the dot in "<plugin>.zsh" is literal — as a regex it also matches the space
    # before the next entry on the plugins=(...) line and reports a phantom double load
    grep -qF "$zp.zsh" "$HOME/.zshrc" 2>/dev/null && via_apt=true
    if [[ "$via_omz" == true && "$via_apt" == true ]]; then
      report_drift "$zp is loaded twice (omz plugin + apt source)." \
        "fix: remove the 'source /usr/share/$zp/...' line from ~/.zshrc"
    elif [[ "$via_omz" == false && "$via_apt" == false ]]; then
      report_drift "$zp not loaded in .zshrc." "fix: bash setup-ubuntu.sh"
    fi
    if [[ "$via_omz" == true && ! -d "$HOME/.oh-my-zsh/custom/plugins/$zp" ]]; then
      report_drift "$zp listed in omz plugins=(...) but not cloned into custom/plugins." \
        "fix: bash setup-ubuntu.sh (clones it)"
    fi
  done

  # oh-my-zsh — framework only. Starship's init runs after it, so any ZSH_THEME is
  # rendered and thrown away. (Double-loaded plugins are checked per plugin above.)
  want_omz=$(grep -m1 '^INSTALL_OMZ=' "$SETUP" 2>/dev/null | grep -oE 'true|false' | head -1 || true)
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    grep -q 'oh-my-zsh.sh' "$HOME/.zshrc" 2>/dev/null \
      || report_drift "~/.oh-my-zsh installed but .zshrc never sources it." "fix: bash setup-ubuntu.sh"
    omz_theme=$(grep -m1 '^ZSH_THEME=' "$HOME/.zshrc" 2>/dev/null || true)
    case "$omz_theme" in
      ''|'ZSH_THEME=""'*|"ZSH_THEME=''"*) report_ok "oh-my-zsh present, prompt left to starship." ;;
      *) report_drift "$omz_theme — starship replaces it, so omz renders a prompt that is discarded." \
           "fix: bash setup-ubuntu.sh (clears ZSH_THEME)" ;;
    esac
  elif [[ "$want_omz" == "true" ]]; then
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
      report_drift "Extra snap: $sn" "remove: sudo snap remove $sn" "adopt: add a 'snap install $sn' step to setup-ubuntu.sh"
    done < <(snap list 2>/dev/null)
  fi

  # pipx tools vs expected (pipx install <name>)
  if command -v pipx >/dev/null 2>&1; then
    mapfile -t EXPECTED_PIPX < <(grep -oE 'pipx install [a-z0-9._-]+' "$SETUP" | awk '{print $3}' | sort -u)
    while read -r pkg; do
      [[ -z "$pkg" ]] && continue
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
      in_list "$pkg" "${EXPECTED_NPM[@]:-}" || \
        report_drift "Extra npm global: $pkg" "remove: npm uninstall -g $pkg" "adopt: add 'npm install -g $pkg' to setup-ubuntu.sh"
    done < <(npm ls -g --depth=0 --parseable 2>/dev/null | sed '1d' | sed -E 's|.*/node_modules/||')
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

# ---------- summary ----------
echo
if [[ $drift -eq 0 ]]; then
  echo "No drift detected — machine matches setup."
else
  echo "$drift drift item(s) found. Each lists a fix and (for extras) how to adopt it into setup."
  echo "Tip: rerun with --apt-extras / --local-bin for the noisier checks."
fi

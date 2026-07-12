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
    local n; n=$(grep -cE "$pat" "$file" 2>/dev/null || echo 0)
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
    check_rc_present "$rc" 'fzf'                 'fzf integration'
  done
  check_rc_marker "$HOME/.zshrc" 'zsh-autosuggestions.zsh'      'zsh-autosuggestions'
  check_rc_marker "$HOME/.zshrc" 'zsh-syntax-highlighting.zsh'  'zsh-syntax-highlighting'

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

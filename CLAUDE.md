# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Idempotent setup scripts for a Windows + WSL2 development environment. There are no build steps, tests, or CI pipelines — the scripts *are* the product.

## Scripts

| File | Language | Run as | Purpose |
|------|----------|--------|---------|
| `bootstrap-windows.ps1` | PowerShell | Administrator | First-run bootstrap for a blank PC: verifies winget, installs Git, creates a VHDX-backed Dev Drive at `D:` (with a boot-time re-attach task), clones this repo to `D:\code\devbox`. Installs no apps; prepares the ground for `setup-windows.ps1`. Fetch-and-run via `irm .../bootstrap-windows.ps1 | iex` |
| `setup-windows.ps1` | PowerShell | Administrator | Installs WezTerm, PowerShell 7, VS Code, Git, Rancher Desktop, PowerToys, 7-Zip, host Node.js, Azure Functions Core Tools, Azure CLI, Claude Code, Codex; writes a managed `~/.wezterm.lua`, configures the Starship prompt, and writes `~/.wslconfig` with 75% of system RAM/CPUs; configures Rancher Desktop VM (moby engine, Kubernetes enabled); relocates npm/NuGet caches onto the `D:` Dev Drive |
| `setup-ubuntu.sh` | Bash | Normal user | Installs apt packages plus the npm-global CLIs (`ncu`, Claude Code, Codex) via `ensure_node`, configures Git globally, generates SSH key, creates `~/code`. Shell stack: Starship is the *only* prompt engine; oh-my-zsh is installed as a framework only (`ZSH_THEME=""`) and loads zsh-autosuggestions/zsh-syntax-highlighting from `custom/plugins` git clones — the apt zsh-autosuggestions (0.7.0) stops drawing inline suggestions in this stack, so the apt packages are a fallback only. Each plugin loads exactly once, via omz or apt, never both. `ensure_shell_history` writes the history/prediction blocks (the zsh counterpart of the Windows PSReadLine block) — see *Managed blocks* below |
| `update-windows.ps1` | PowerShell | Administrator | Maintenance-only refresh of an existing machine: OS/Defender/Store updates, `wsl --update`, `winget upgrade --all`, global npm packages. Installs nothing new |
| `update-ubuntu.sh` | Bash | Normal user | Maintenance-only refresh: apt upgrade plus starship, zoxide, git-delta, lazygit, stern, k9s, kubectx, npm globals, pipx tools. `--skip-*` flags opt out |
| `audit-windows.ps1` | PowerShell | Normal user | Read-only drift report: winget apps / VS Code extensions / npm globals not in (or missing from) setup, plus managed-config drift (WezTerm, PS profiles, `.wslconfig`, cache env vars, Git), plus startup & services (verifies the `DevboxMountDevDrive` task and `ssh-agent` StartupType, then inventories non-Microsoft autostart: logon/boot tasks, Run keys, Startup folder, third-party auto services). Changes nothing; prints two-way reconcile hints |
| `audit-ubuntu.sh` | Bash | Normal user | Read-only drift report: expected CLIs, managed rc blocks (presence, duplication, and — for the two order-sensitive zsh history blocks — *position*), effective `HISTSIZE`/`SAVEHIST` against `SHELL_HISTORY_SIZE`, the inline-suggestion colour (flags the invisible stock `fg=8`), `starship.toml`, `/etc/wsl.conf`, Git, default shell, oh-my-zsh (present, sourced, `ZSH_THEME` empty, no plugins loaded twice), plus extra snap/pipx/npm apps, plus startup & services (systemd running-state, then inventories units enabled against their vendor preset and user crontab), plus a docker-engine check (flags shadow apt/snap dockerds fighting Rancher Desktop for the socket, and verifies the CLI + answering daemon are Rancher's). `--apt-extras` / `--local-bin` add noisier checks. Changes nothing; prints two-way reconcile hints |

All scripts are safe to rerun (idempotent). The `audit-*` scripts are additionally read-only.

The audit scripts derive their "expected" state by parsing the setup scripts — `audit-windows.ps1` AST-extracts the `$Config` hashtable and regexes `-Id`/`npm install -g` calls out of `setup-windows.ps1`; `audit-ubuntu.sh` parses the `APT_PACKAGES` array plus `ensure_pkg`/`ensure_command` calls out of `setup-ubuntu.sh`. Keep that parsing in sync when the setup scripts change shape (e.g. renaming `$Config` keys or the package array).

## Running the scripts

```powershell
# Windows — must be run as Administrator
.\setup-windows.ps1
```

```bash
# Ubuntu/WSL — GIT_NAME/GIT_EMAIL auto-detect from the Windows (Entra) user on WSL
# (UPN + logon display name); export them to override, or set
# AUTO_DETECT_GIT_IDENTITY=false to disable. Still required if detection finds nothing.
bash setup-ubuntu.sh
```

## Coding conventions

### All scripts
- All user-configurable values live at the top in a clearly marked `PARAMETERS` section. Core logic stays untouched when users customise.
- Status output uses `✓` (already done), `→` (taking action), `⚠` (warning).

### Bash (`setup-ubuntu.sh`, `update-ubuntu.sh`)
- Strict mode: `set -euo pipefail`
- Functions: `snake_case` verbs — `ensure_pkg`, `ensure_dir`, `ensure_git_config`, `ensure_ssh_key`, `ensure_command`
- Variables: `UPPER_CASE` for env/config, `lower_case` locals

### PowerShell (`setup-windows.ps1`, `bootstrap-windows.ps1`, `update-windows.ps1`)
- Strict mode: `Set-StrictMode -Version Latest`, `$ErrorActionPreference = "Stop"`
- Functions: `PascalCase` verb-noun — `Ensure-WSL`, `Install-WingetPackage`, `Get-SystemResources`
- Config: top-level `$Config` hashtable; `$null` values are resolved at runtime (e.g. WSL memory auto-detects to 75% of system RAM via `Get-SystemResources` + `Get-WslAllocation`)
- Rancher Desktop settings are merged into its existing `settings.json` — never wholesale replaced

### Idempotency pattern
Check current state, skip if already correct, act and report if not. Every `Ensure-*` / `ensure_*` function follows this pattern.

Managed blocks written into user config (PowerShell profiles, rc files) are delimited by `# --- devbox: <marker> ... # --- end devbox block ---` and rewritten **in place** by `Set-ManagedProfileBlock` (PowerShell) / `set_managed_block` (Bash), not merely appended when the marker is absent. Marker-presence-only checks strand every existing machine on the old block the moment the snippet changes. `audit-windows.ps1` cross-checks the installed block against the here-string it parses out of the setup function, so a stale block reports as drift.

Older Ubuntu blocks (`devbox eza aliases`, `devbox terminal cwd`) predate this and still use bare markers with append-if-absent. New Bash blocks should use `set_managed_block`.

**Load order is part of the contract for the zsh history blocks.** `devbox: zsh history` must sit *above* the oh-my-zsh source line (omz's `lib/history.zsh` reassigns `HISTSIZE`/`SAVEHIST`, and zsh-autosuggestions only honours `ZSH_AUTOSUGGEST_*` already set when it loads); `devbox: zsh history keys` must sit *below* the fzf integration (fzf binds `^I`). Hence `ensure_shell_history` runs after `ensure_omz`/`ensure_fzf_shell_integration`, splices with `insert_before_anchor` on first write, and rewrites in place afterwards so the position survives. `audit-ubuntu.sh` compares line numbers rather than trusting marker presence — a block in the wrong place fails silently otherwise.

Two traps worth remembering, both of which produced silent no-ops here: awk turns the `\$` of an anchor like `\$ZSH/oh-my-zsh.sh` into a bare `$` (end-of-line in ERE, matches nothing), so `insert_before_anchor` matches with `index()` on a literal instead; and `grep -c` already prints `0` on no match, so a trailing `|| echo 0` yields `"0\n0"` and breaks every `[[ -eq ]]` downstream.

## DevContainer

`.devcontainer/` defines an Ubuntu 22.04 container used when developing inside this repo via VS Code. Git identity is injected via `containerEnv` in `devcontainer.json` — edit those values to personalise.

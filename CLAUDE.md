# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Idempotent setup scripts for a Windows + WSL2 development environment. There are no build steps, tests, or CI pipelines — the scripts *are* the product.

## Scripts

| File | Language | Run as | Purpose |
|------|----------|--------|---------|
| `bootstrap-windows.ps1` | PowerShell | Administrator | First-run bootstrap for a blank PC: verifies winget, installs Git, creates a VHDX-backed Dev Drive at `D:` (with a boot-time re-attach task), clones this repo to `D:\code\devbox`. Installs no apps; prepares the ground for `setup-windows.ps1`. Fetch-and-run via `irm .../bootstrap-windows.ps1 | iex` |
| `setup-windows.ps1` | PowerShell | Administrator | Installs WezTerm, PowerShell 7, VS Code, Git, Rancher Desktop, PowerToys, 7-Zip, host Node.js, Azure Functions Core Tools, Azure CLI; writes a managed `~/.wezterm.lua`, configures the Starship prompt, and writes `~/.wslconfig` with 75% of system RAM/CPUs; configures Rancher Desktop VM (moby engine, Kubernetes enabled); relocates npm/NuGet caches onto the `D:` Dev Drive |
| `setup-ubuntu.sh` | Bash | Normal user | Installs apt packages, configures Git globally, generates SSH key, creates `~/code` |
| `update-windows.ps1` | PowerShell | Administrator | Maintenance-only refresh of an existing machine: OS/Defender/Store updates, `wsl --update`, `winget upgrade --all`, global npm packages. Installs nothing new |
| `update-ubuntu.sh` | Bash | Normal user | Maintenance-only refresh: apt upgrade plus starship, zoxide, git-delta, lazygit, stern, k9s, kubectx, npm globals, pipx tools. `--skip-*` flags opt out |
| `audit-windows.ps1` | PowerShell | Normal user | Read-only drift report: winget apps / VS Code extensions / npm globals not in (or missing from) setup, plus managed-config drift (WezTerm, PS profiles, `.wslconfig`, cache env vars, Git). Changes nothing; prints two-way reconcile hints |
| `audit-ubuntu.sh` | Bash | Normal user | Read-only drift report: expected CLIs, managed rc blocks, `starship.toml`, `/etc/wsl.conf`, Git, default shell, plus extra snap/pipx/npm apps. `--apt-extras` / `--local-bin` add noisier checks. Changes nothing; prints two-way reconcile hints |

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

## DevContainer

`.devcontainer/` defines an Ubuntu 22.04 container used when developing inside this repo via VS Code. Git identity is injected via `containerEnv` in `devcontainer.json` — edit those values to personalise.

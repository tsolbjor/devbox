# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Idempotent setup scripts for a Windows + WSL2 development environment. There are no build steps, tests, or CI pipelines — the scripts *are* the product.

## Scripts

| File | Language | Run as | Purpose |
|------|----------|--------|---------|
| `setup-windows.ps1` | PowerShell | Administrator | Installs Windows Terminal, VS Code, Rancher Desktop, WSL2/Ubuntu; writes `~/.wslconfig` with 75% of system RAM/CPUs; configures Rancher Desktop VM (moby engine, Kubernetes enabled) |
| `setup-ubuntu.sh` | Bash | Normal user | Installs apt packages, configures Git globally, generates SSH key, creates `~/code` |

Both scripts are safe to rerun (idempotent).

## Running the scripts

```powershell
# Windows — must be run as Administrator
.\setup-windows.ps1
```

```bash
# Ubuntu/WSL — GIT_NAME and GIT_EMAIL required when SET_GIT_DEFAULTS=true
export GIT_NAME="Your Name"
export GIT_EMAIL="your@email.com"
bash setup-ubuntu.sh
```

## Coding conventions

### Both scripts
- All user-configurable values live at the top in a clearly marked `PARAMETERS` section. Core logic stays untouched when users customise.
- Status output uses `✓` (already done), `→` (taking action), `⚠` (warning).

### Bash (`setup-ubuntu.sh`)
- Strict mode: `set -euo pipefail`
- Functions: `snake_case` verbs — `ensure_pkg`, `ensure_dir`, `ensure_git_config`, `ensure_ssh_key`, `ensure_command`
- Variables: `UPPER_CASE` for env/config, `lower_case` locals

### PowerShell (`setup-windows.ps1`)
- Strict mode: `Set-StrictMode -Version Latest`, `$ErrorActionPreference = "Stop"`
- Functions: `PascalCase` verb-noun — `Ensure-WSL`, `Install-WingetPackage`, `Get-SystemResources`
- Config: top-level `$Config` hashtable; `$null` values are resolved at runtime (e.g. WSL memory auto-detects to 75% of system RAM via `Get-SystemResources` + `Get-WslAllocation`)
- Rancher Desktop settings are merged into its existing `settings.json` — never wholesale replaced

### Idempotency pattern
Check current state, skip if already correct, act and report if not. Every `Ensure-*` / `ensure_*` function follows this pattern.

## DevContainer

`.devcontainer/` defines an Ubuntu 22.04 container used when developing inside this repo via VS Code. Git identity is injected via `containerEnv` in `devcontainer.json` — edit those values to personalise.

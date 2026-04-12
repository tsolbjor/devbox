# Contributing

## Dev environment

A `.devcontainer/` is included for working on the scripts themselves. Open the repo in VS Code and select **Reopen in Container** — it provides Ubuntu 22.04 with git, build tools, ripgrep, fd, jq, and the GitHub CLI pre-installed.

Before building the container, set your identity in `.devcontainer/devcontainer.json`:

```json
"containerEnv": {
  "GIT_NAME": "Your Name",
  "GIT_EMAIL": "your@email.com"
}
```

## Design principles

**Idempotency is non-negotiable.** Every operation must be safe to run multiple times on the same machine. Use the `ensure_*` / `Ensure-*` pattern: check current state first, skip if already correct, act and report if not.

**Parameters at the top, implementation below.** All user-configurable values live in a clearly marked `PARAMETERS` section. Users should never need to touch the implementation to do common customisation.

**Fail loudly, skip gracefully.** Hard prerequisites (missing winget, unset `GIT_NAME`) should throw/exit immediately with a clear message. Optional steps that can't run yet (Rancher Desktop not launched, git not in PATH) should warn and continue.

## Conventions

### Bash (`setup-ubuntu.sh`)

- Strict mode: `set -euo pipefail`
- Function names: `snake_case` verbs — `ensure_pkg`, `ensure_kubectl`, `ensure_wsl_conf`
- Variables: `UPPER_CASE` for env/config, `lower_case` for locals inside functions
- Output symbols: `✓` already satisfied · `→` taking action · `⚠` warning

```bash
ensure_thing() {
  if <check>; then
    echo "✓ thing already done"
    return
  fi
  echo "→ Doing thing"
  <action>
  echo "✓ thing done"
}
```

### PowerShell (`setup-windows.ps1`)

- Strict mode: `Set-StrictMode -Version Latest` + `$ErrorActionPreference = "Stop"`
- Function names: `PascalCase` verb-noun — `Ensure-WSL`, `Install-WingetPackage`, `Get-SystemResources`
- Config: top-level `$Config` hashtable; `$null` values are resolved at runtime (e.g. WSL memory auto-detects to 75% of system RAM)
- Output: `Write-Host` with `-ForegroundColor Green` (✓), `Cyan` (→), `Write-Warning` (⚠)
- Target PowerShell 5.1 compatibility — avoid PS7-only syntax (`??`, `?:`)

```powershell
function Ensure-Thing {
  param([Parameter(Mandatory=$true)][string]$Name)
  if (<check>) {
    Write-Host "✓ Already done: $Name" -ForegroundColor Green
    return
  }
  Write-Host "→ Doing: $Name" -ForegroundColor Cyan
  <action>
  Write-Host "✓ Done: $Name" -ForegroundColor Green
}
```

## Testing

Run the script on a clean machine (or a fresh WSL distro) and verify everything installs correctly. Then run it a second time — the second run should produce only `✓` lines and make no changes to the system.

For the Windows script, the Rancher Desktop and Windows Terminal functions require those apps to have been launched at least once before the settings files exist.

## Submitting changes

Open a pull request against `main`. Keep changes focused — one logical change per PR. The scripts are the product; update the README if what gets installed or configured changes.

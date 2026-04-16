# GitHub Copilot Instructions for devbox

## Repository Overview

This repository provides automated development environment setup scripts for Windows and Ubuntu/WSL. The scripts are designed to be idempotent, meaning they can be run multiple times safely without causing duplicate installations or configuration issues.

## Core Principles

### Idempotency
- All scripts must check for existing installations/configurations before making changes
- Use "ensure" patterns: check if something exists, if not, create/install it
- Print status messages indicating whether an action was taken or already satisfied
- Examples:
  - `✓ Already installed: <package>`
  - `→ Installing: <package>`

### Shell Script Style (Bash)
- Use `#!/usr/bin/env bash` shebang
- Enable strict mode: `set -euo pipefail`
- Use functions with descriptive names: `ensure_pkg()`, `ensure_dir()`, `ensure_git_config()`
- Prefix helper function names with action verbs (ensure, check, test, install)
- Use lowercase with underscores for variable names: `git_name`, `code_dir`
- Use uppercase for constants and environment variables: `GIT_NAME`, `CODE_DIR`
- Provide clear user feedback with `echo` statements using symbols: ✓ for success, → for actions, ⚠ for warnings

### PowerShell Style
- Use `Set-StrictMode -Version Latest` and `$ErrorActionPreference = "Stop"`
- Follow PowerShell naming conventions: PascalCase for functions (e.g., `Ensure-Winget`, `Install-WingetPackage`)
- Use approved PowerShell verbs (Get, Set, Test, Ensure, Install, etc.)
- Use parameter validation with `[Parameter(Mandatory=$true)]`
- Provide clear user feedback with color-coded `Write-Host` statements
- Use hashtables (`@{}`) for configuration objects

### Configuration Pattern
- Keep all user-configurable parameters at the top of scripts
- Use environment variables with defaults in bash: `${VAR_NAME:-default_value}`
- Use hashtable configuration objects in PowerShell: `$Config = @{}`
- Make scripts customizable without modifying core logic
- Document all configuration options

### Error Handling
- Use defensive checks before operations
- Provide clear error messages when prerequisites are missing
- Gracefully handle edge cases (e.g., missing tools, network issues)
- Return meaningful exit codes

### Package Management
- Use native package managers: `apt-get` for Ubuntu, `winget` for Windows
- Check if packages are already installed before attempting installation
- Use `--accept-source-agreements` and `--accept-package-agreements` flags for winget to avoid prompts
- Keep package lists minimal and focused on essential development tools

### Git Configuration
- Use `git config --global` for system-wide settings
- Check current values before setting to avoid unnecessary operations
- Support common Git configuration: user.name, user.email, init.defaultBranch, core.autocrlf

### SSH Key Management
- Default to ed25519 keys (more secure and modern)
- Check for existing keys before generating new ones
- Use email address as key comment for identification
- Display public key after generation for easy copying

## Code Structure

### Bash Scripts
```bash
# 1. Parameters section with environment variable defaults
GIT_NAME="${GIT_NAME:-Default Name}"

# 2. Helper functions
ensure_pkg() {
  # Implementation with idempotency checks
}

# 3. Main execution logic
log "Section name"
# Actual work
```

### PowerShell Scripts
```powershell
# 1. Configuration hashtable
$Config = @{
  OptionName = $value
}

# 2. Helper functions with proper verb-noun naming
function Ensure-Package {
  param([Parameter(Mandatory=$true)][string]$Name)
  # Implementation
}

# 3. Main execution (after functions)
```

## Testing and Validation

- Scripts should be tested on fresh installations
- Test idempotency by running scripts multiple times
- Verify that no errors occur on repeated runs
- Check that the script handles both clean state and already-configured state

## Common Patterns

### Checking if a command exists (Bash)
```bash
ensure_command() {
  command -v "$1" >/dev/null 2>&1
}
```

### Checking if a package is installed (Bash)
```bash
is_pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}
```

### Installing packages idempotently (PowerShell)
```powershell
function Install-WingetPackage {
  param([Parameter(Mandatory=$true)][string]$Id)
  $list = winget list --id $Id --accept-source-agreements 2>$null | Out-String
  if ($list -match [regex]::Escape($Id)) {
    Write-Host "✓ Already installed: $Id" -ForegroundColor Green
    return
  }
  Write-Host "→ Installing: $Id" -ForegroundColor Cyan
  winget install --id $Id -e --silent --accept-package-agreements --accept-source-agreements
}
```

## Documentation Standards

- Keep README.md up to date with script capabilities
- Document all configuration options with examples
- Include system requirements clearly
- Provide quick start instructions for both Windows and Ubuntu
- List all installed packages/tools

## Security Considerations

- Never hardcode credentials or sensitive data
- Use SSH key authentication over password authentication
- Prefer ed25519 keys over older RSA keys
- Validate user input when applicable
- Run Windows scripts with Administrator privileges only when necessary

## Best Practices

- Keep scripts focused and single-purpose
- Avoid unnecessary complexity
- Make scripts self-documenting with clear variable names and comments
- Provide helpful output that guides users through the process
- Handle edge cases gracefully
- Support both fresh installations and updates

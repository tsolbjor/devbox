# devbox
Automated development environment setup for Windows and Ubuntu/WSL. This project provides idempotent setup scripts to configure a complete development machine with essential tools, Git configuration, SSH keys, and system settings.

## Features

- **Windows Setup**: Automated installation of Windows Terminal, VS Code, WSL 2, Rancher Desktop, and VS Code extensions
- **Ubuntu/WSL Setup**: Installation of development packages (git, buildtools, ripgrep, etc.), Git configuration, and SSH key generation
- **Idempotent Scripts**: Safe to run multiple times; scripts check for existing installations before installing
- **Customizable Parameters**: Edit configuration at the top of each script to customize behavior
- **Git & SSH Automation**: Automatic Git configuration and SSH key generation with configurable options

## Quick Start

### Windows Setup

1. Open PowerShell as Administrator
2. Run the setup script:
   ```powershell
   .\setup-windows.ps1
   ```
3. The script will:
   - Enable WSL 2 and Virtual Machine Platform features
   - Install Windows Terminal, VS Code, and Rancher Desktop
   - Set up Ubuntu distribution in WSL
   - Configure VS Code extensions for remote development
   - Set WSL resource limits

### Ubuntu/WSL Setup

1. Open a bash terminal in Ubuntu/WSL
2. Run the setup script:
   ```bash
   bash setup-ubuntu.sh
   ```
3. The script will:
   - Install essential development packages
   - Configure Git user information
   - Generate SSH keys (ed25519)
   - Create development directories
   - Set up Git defaults

## Configuration

### Windows ([setup-windows.ps1](setup-windows.ps1))

Edit the `$Config` hashtable at the top of the script:

```powershell
$Config = @{
  InstallWindowsTerminal = $true
  InstallVSCode          = $true
  InstallRancherDesktop   = $true
  EnsureWSL              = $true
  WslDefaultVersion      = 2
  UbuntuDistroName       = "Ubuntu"
  WslConfig = @{
    memory     = "8GB"
    processors = 4
  }
  VSCodeExtensions = @(
    "ms-vscode-remote.remote-wsl",
    "ms-vscode-remote.remote-containers"
  )
}
```

### Ubuntu/WSL ([setup-ubuntu.sh](setup-ubuntu.sh))

Edit environment variables at the top of the script:

```bash
GIT_NAME="${GIT_NAME:-Thomas Solbjør}"
GIT_EMAIL="${GIT_EMAIL:-thomas.solbjor@fortedigital.com}"
CODE_DIR="${CODE_DIR:-$HOME/code}"
GIT_DEFAULT_BRANCH="${GIT_DEFAULT_BRANCH:-main}"
SSH_KEY_TYPE="${SSH_KEY_TYPE:-ed25519}"
INSTALL_GITHUB_CLI="${INSTALL_GITHUB_CLI:-true}"
SET_GIT_DEFAULTS="${SET_GIT_DEFAULTS:-true}"
ENSURE_SSH_KEY="${ENSURE_SSH_KEY:-true}"
```

## System Requirements

### Windows Setup
- Windows 10/11 (Pro, Enterprise, or Home with WSL support)
- Administrator privileges
- winget package manager installed

### Ubuntu/WSL Setup
- Ubuntu 20.04 LTS or later
- bash shell
- sudo access (for apt-get)

## Installed Packages

### Windows
- Windows Terminal
- Visual Studio Code
- Rancher Desktop (Docker alternative)
- VS Code extensions for remote development (WSL, Dev Containers)

### Ubuntu/WSL
- Git, curl, unzip
- Build tools (build-essential, gcc, make)
- Development utilities (jq, ripgrep, fd-find, gnupg)
- GitHub CLI (optional)

## Files

- [setup-windows.ps1](setup-windows.ps1) - Windows environment setup
- [setup-ubuntu.sh](setup-ubuntu.sh) - Ubuntu/WSL environment setup
- [README.md](README.md) - This file

## Notes

- Scripts are idempotent—safe to run multiple times
- The Windows script requires Administrator privileges
- SSH keys are generated with ed25519 algorithm by default (highly secure)
- Git is configured globally across the system
- Code directory defaults to `~/code` and can be customized
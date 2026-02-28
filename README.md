# devbox
Automated development environment setup for Windows and Ubuntu/WSL. This project provides idempotent setup scripts to configure a complete development machine with essential tools, Git configuration, SSH keys, and system settings.

## Features

- **DevContainer Support**: Pre-configured development container for VS Code with all essential tools
- **Windows Setup**: Automated installation of Windows Terminal, VS Code, WSL 2, Rancher Desktop, and VS Code extensions
- **Ubuntu/WSL Setup**: Installation of development packages (git, buildtools, ripgrep, etc.), Git configuration, and SSH key generation
- **Idempotent Scripts**: Safe to run multiple times; scripts check for existing installations before installing
- **Customizable Parameters**: Edit configuration at the top of each script to customize behavior
- **Git & SSH Automation**: Automatic Git configuration and SSH key generation with configurable options

## Quick Start

### Using DevContainer (Recommended)

The easiest way to get started is using VS Code Dev Containers:

1. Install [VS Code](https://code.visualstudio.com/) and the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) or [Rancher Desktop](https://rancherdesktop.io/) (with containerization enabled)
3. Clone this repository
4. Open the repository in VS Code
5. When prompted, click **"Reopen in Container"** (or press `F1` and select "Dev Containers: Reopen in Container")
6. VS Code will build and start the development container with all tools pre-installed

The devcontainer includes:
- Ubuntu 22.04 LTS base
- Git, build-essential, gcc, make
- jq, ripgrep, fd-find
- GitHub CLI (v2.62.0)
- Preconfigured Git defaults

#### Customizing the DevContainer

Edit `.devcontainer/devcontainer.json` to customize the Git configuration:

```json
"containerEnv": {
  "GIT_NAME": "Your Name",
  "GIT_EMAIL": "your.email@example.com"
}
```

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
GIT_NAME="${GIT_NAME:-Your Name}"
GIT_EMAIL="${GIT_EMAIL:-your.email@example.com}"
CODE_DIR="${CODE_DIR:-$HOME/code}"
GIT_DEFAULT_BRANCH="${GIT_DEFAULT_BRANCH:-main}"
SSH_KEY_TYPE="${SSH_KEY_TYPE:-ed25519}"
INSTALL_GITHUB_CLI="${INSTALL_GITHUB_CLI:-true}"
SET_GIT_DEFAULTS="${SET_GIT_DEFAULTS:-true}"
ENSURE_SSH_KEY="${ENSURE_SSH_KEY:-true}"
```

## System Requirements

### DevContainer
- VS Code with Dev Containers extension
- Docker Desktop, Rancher Desktop, or compatible container runtime
- 4GB+ RAM available for the container

### Windows Setup
- Windows 10/11 (Pro, Enterprise, or Home with WSL support)
- Administrator privileges
- winget package manager installed

### Ubuntu/WSL Setup
- Ubuntu 20.04 LTS or later
- bash shell
- sudo access (for apt-get)

## Installed Packages

### DevContainer
- Ubuntu 22.04 LTS base image
- Git, curl, unzip
- Build tools (build-essential, gcc, make)
- Development utilities (jq, ripgrep, fd-find, gnupg)
- GitHub CLI (v2.62.0)

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

- [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) - DevContainer configuration
- [.devcontainer/Dockerfile](.devcontainer/Dockerfile) - DevContainer image definition
- [setup-windows.ps1](setup-windows.ps1) - Windows environment setup
- [setup-ubuntu.sh](setup-ubuntu.sh) - Ubuntu/WSL environment setup
- [README.md](README.md) - This file

## Notes

- **DevContainer** provides a consistent, isolated development environment across all platforms
- Scripts are idempotent—safe to run multiple times
- The Windows script requires Administrator privileges
- SSH keys are generated with ed25519 algorithm by default (highly secure)
- Git is configured globally across the system
- Code directory defaults to `~/code` and can be customized
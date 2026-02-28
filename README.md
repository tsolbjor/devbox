# devbox
Automated development environment setup for Windows and Ubuntu/WSL. This project provides idempotent setup scripts to configure a complete development machine with essential tools, Git configuration, SSH keys, and system settings.

## Features

- **DevContainer Support**: Pre-configured development container for VS Code with all essential tools
- **Windows Setup**: Automated installation of Windows Terminal, VS Code, WSL 2, Rancher Desktop, and VS Code extensions
- **Ubuntu/WSL Setup**: Installation of development packages (git, buildtools, ripgrep, etc.), Git configuration, and SSH key generation
- **App Installation Scripts**: Comprehensive scripts for installing development tools and applications on both Windows and Ubuntu/WSL
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

### Installing Additional Development Apps

After completing the initial setup, you can install additional development tools and applications:

#### Windows Apps Installation

1. Open PowerShell as Administrator
2. Run the apps installation script:
   ```powershell
   .\install-windows-apps.ps1
   ```
3. The script will install:
   - .NET SDK
   - Node.js (LTS)
   - TypeScript, Azure Functions Core Tools (via npm)
   - Azure CLI, Azure Developer CLI, AzCopy
   - oh-my-posh
   - PowerToys
   - devtunnel
   - 7zip
   - JetBrains Toolbox
   - Postman
   - Figma
   - WinSCP
   - GitHub Copilot CLI

#### Ubuntu/WSL Apps Installation

1. Open a bash terminal in Ubuntu/WSL
2. Run the apps installation script:
   ```bash
   bash install-ubuntu-apps.sh
   ```
3. The script will install:
   - .NET SDK
   - Node.js and nvm
   - TypeScript, Azure Functions Core Tools (via npm)
   - Azure CLI, Azure Developer CLI, AzCopy
   - oh-my-zsh
   - oh-my-posh
   - 7zip (p7zip-full)
   - GitHub Copilot CLI
   - Postman CLI
   - JetBrains Toolbox

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

Set environment variables or edit the script:

```bash
# Required (set before running or edit script)
export GIT_NAME="Your Name"
export GIT_EMAIL="your.email@example.com"

# Optional configuration (with defaults)
CODE_DIR="${CODE_DIR:-$HOME/code}"
GIT_DEFAULT_BRANCH="${GIT_DEFAULT_BRANCH:-main}"
SSH_KEY_TYPE="${SSH_KEY_TYPE:-ed25519}"
INSTALL_GITHUB_CLI="${INSTALL_GITHUB_CLI:-true}"
SET_GIT_DEFAULTS="${SET_GIT_DEFAULTS:-true}"
ENSURE_SSH_KEY="${ENSURE_SSH_KEY:-true}"
```

**Note:** The script will exit with an error if `GIT_NAME` or `GIT_EMAIL` are not set when `SET_GIT_DEFAULTS=true`.

### Windows Apps ([install-windows-apps.ps1](install-windows-apps.ps1))

Edit the `$Config` hashtable at the top of the script:

```powershell
$Config = @{
  DotNetVersion           = "8.0"
  NodeVersion             = "20"
  InstallDotNet           = $true
  InstallNodeJS           = $true
  InstallAzureCLI         = $true
  InstallAzureDeveloperCLI = $true
  InstallAzCopy           = $true
  InstallOhMyPosh         = $true
  InstallPowerToys        = $true
  InstallDevTunnel        = $true
  Install7Zip             = $true
  InstallJetBrainsToolbox = $true
  InstallPostman          = $true
  InstallFigma            = $true
  InstallWinSCP           = $true
  InstallTypeScript       = $true
  InstallAzureFunctions   = $true
  InstallCopilotCLI       = $true
}
```

### Ubuntu/WSL Apps ([install-ubuntu-apps.sh](install-ubuntu-apps.sh))

Set environment variables or edit the script:

```bash
# Node.js and .NET versions
NODE_VERSION="${NODE_VERSION:-20}"
DOTNET_VERSION="${DOTNET_VERSION:-8.0}"

# Optional installs (set to "false" to skip)
INSTALL_DOTNET="${INSTALL_DOTNET:-true}"
INSTALL_NODEJS="${INSTALL_NODEJS:-true}"
INSTALL_AZURE_CLI="${INSTALL_AZURE_CLI:-true}"
INSTALL_AZURE_DEVOPS_CLI="${INSTALL_AZURE_DEVOPS_CLI:-true}"
INSTALL_AZCOPY="${INSTALL_AZCOPY:-true}"
INSTALL_OH_MY_ZSH="${INSTALL_OH_MY_ZSH:-true}"
INSTALL_OH_MY_POSH="${INSTALL_OH_MY_POSH:-true}"
INSTALL_7ZIP="${INSTALL_7ZIP:-true}"
INSTALL_COPILOT_CLI="${INSTALL_COPILOT_CLI:-true}"
INSTALL_POSTMAN="${INSTALL_POSTMAN:-true}"
INSTALL_JETBRAINS_TOOLBOX="${INSTALL_JETBRAINS_TOOLBOX:-true}"
INSTALL_TYPESCRIPT="${INSTALL_TYPESCRIPT:-true}"
INSTALL_AZFUNC="${INSTALL_AZFUNC:-true}"
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

### Windows Apps Installation
- Windows 10/11 with winget package manager
- Administrator privileges (recommended)
- Internet connection for downloading packages

### Ubuntu/WSL Apps Installation
- Ubuntu 20.04 LTS or later
- bash shell
- sudo access (for apt-get)
- Internet connection for downloading packages

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

### Windows Apps (via install-windows-apps.ps1)
- .NET SDK 8.0
- Node.js LTS with npm
- TypeScript, Azure Functions Core Tools (via npm)
- Azure CLI, Azure Developer CLI, AzCopy
- oh-my-posh
- PowerToys
- devtunnel (via dotnet tool)
- 7zip
- JetBrains Toolbox
- Postman
- Figma
- WinSCP
- GitHub Copilot CLI (via npm)

### Ubuntu/WSL Apps (via install-ubuntu-apps.sh)
- .NET SDK 8.0
- Node.js (via nvm) with npm
- TypeScript, Azure Functions Core Tools (via npm)
- Azure CLI, Azure Developer CLI, AzCopy
- oh-my-zsh
- oh-my-posh
- 7zip (p7zip-full)
- GitHub Copilot CLI (via npm)
- Postman CLI
- JetBrains Toolbox

## Files

- [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) - DevContainer configuration
- [.devcontainer/Dockerfile](.devcontainer/Dockerfile) - DevContainer image definition
- [setup-windows.ps1](setup-windows.ps1) - Windows environment setup
- [setup-ubuntu.sh](setup-ubuntu.sh) - Ubuntu/WSL environment setup
- [install-windows-apps.ps1](install-windows-apps.ps1) - Windows development apps installation
- [install-ubuntu-apps.sh](install-ubuntu-apps.sh) - Ubuntu/WSL development apps installation
- [README.md](README.md) - This file

## Notes

- **DevContainer** provides a consistent, isolated development environment across all platforms
- Scripts are idempotent—safe to run multiple times
- The Windows script requires Administrator privileges
- SSH keys are generated with ed25519 algorithm by default (highly secure)
- Git is configured globally across the system
- Code directory defaults to `~/code` and can be customized
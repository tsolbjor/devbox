# devbox

Automated, idempotent setup scripts for a Windows + WSL2 development environment.

## Prerequisites

**Windows** (`setup-windows.ps1`)
- Windows 10/11 with WSL support
- [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/) (App Installer from the Microsoft Store)
- PowerShell run as Administrator

**Ubuntu / WSL** (`setup-ubuntu.sh`)
- Ubuntu 20.04 LTS or later inside WSL2
- sudo access

## Quick Start

### 1. Windows

Open PowerShell as Administrator:

```powershell
.\setup-windows.ps1
```

Installs and configures:

| Category | What gets set up |
|---|---|
| Apps | Windows Terminal, VS Code, Git, Rancher Desktop, PowerToys, 7-Zip |
| Fonts | Cascadia Code, JetBrains Mono Nerd Font |
| Cloud CLIs | Azure CLI, AWS CLI, Google Cloud SDK |
| VS Code | Remote WSL, Dev Containers, Docker extensions |
| WSL | Ubuntu distro, resource limits (75% RAM/CPU), mirrored networking, swap disabled |
| Rancher Desktop | moby engine (Docker-compatible), Kubernetes enabled |
| Windows Terminal | JetBrains Mono font, One Half Dark theme, bar cursor, bell off |
| PowerShell prompt | Oh My Posh (jandedobbeleer theme) for PS5 and PS7 |
| System | Long path support, OpenSSH Agent, Defender exclusion for WSL vhdx |
| Git | autocrlf, defaultBranch, pull.rebase, push.autoSetupRemote |

### 2. Ubuntu / WSL

Inside your WSL Ubuntu terminal:

```bash
export GIT_NAME="Your Name"
export GIT_EMAIL="your@email.com"
bash setup-ubuntu.sh
```

Installs and configures:

| Category | What gets set up |
|---|---|
| Shell | zsh (set as default), Oh My Posh, fzf with key bindings |
| Dev tools | git, build-essential, ripgrep, fd, jq, wget, zip, GitHub CLI |
| Kubernetes | kubectl, helm, k9s, kubectx, kubens |
| Git | user config, defaultBranch, pull.rebase, push.autoSetupRemote |
| SSH | ed25519 key pair |
| System | /etc/wsl.conf (automount metadata, systemd) |

After the script finishes it prints your SSH public key and next steps.

## Customisation

Both scripts have a `PARAMETERS` section at the very top — edit values there before running. No changes to the implementation section are needed for common adjustments.

**Windows** — remove entries from `Fonts`, `CloudCLIs`, or `VSCodeExtensions`; change the Oh My Posh theme; override `WslConfig` memory/CPU values explicitly instead of auto-detecting.

**Ubuntu** — set `INSTALL_KUBECTL=false` to skip Kubernetes tools; change `OH_MY_POSH_THEME` to any name from [ohmyposh.dev/docs/themes](https://ohmyposh.dev/docs/themes); set `WSL_ENABLE_SYSTEMD=false` on older Windows builds.

## System requirements

| | Minimum |
|---|---|
| Windows | Windows 10/11 (Home, Pro, or Enterprise) |
| RAM | 16 GB recommended (scripts allocate 75% to WSL) |
| WSL networking | `networkingMode=mirrored` requires Windows 11 22H2+ |
| Systemd in WSL | Requires Windows 11 22H2+ / WSL 2.0 |

# devbox

Automated, idempotent setup scripts for a Windows + WSL2 development environment.

> 📄 **New here?** See the [**terminal cheatsheet**](CHEATSHEET.md) for WezTerm, Starship,
> and CLI-addon keyboard shortcuts and how-tos.

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

A blank, Entra-joined PC has no Git and (usually) no `D:` drive yet, so start with
the **bootstrap**. Open **PowerShell as Administrator** and run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
irm https://raw.githubusercontent.com/tsolbjor/devbox/main/bootstrap-windows.ps1 | iex
```

`bootstrap-windows.ps1` verifies winget, installs Git, creates a **Dev Drive** at
`D:` (a VHDX-backed ReFS volume — needs no free partition, re-attached at boot),
and clones this repo to `D:\code\devbox`. It installs no apps and doesn't touch
WSL — it just prepares the ground, then prints the next command.

Then run the full setup from the cloned folder:

```powershell
Set-Location D:\code\devbox
.\setup-windows.ps1
```

> Already have Git and a `D:` drive? Skip the bootstrap — clone the repo and run
> `.\setup-windows.ps1` directly.

Installs and configures:

| Category | What gets set up |
|---|---|
| Apps | WezTerm, PowerShell 7, VS Code, Git, Rancher Desktop, PowerToys, 7-Zip |
| Fonts | Cascadia Code, JetBrains Mono Nerd Font |
| Cloud CLIs | Azure CLI, AWS CLI, Google Cloud SDK |
| VS Code | Remote WSL, Dev Containers, Docker extensions |
| WSL | Ubuntu distro, resource limits (75% RAM/CPU), mirrored networking, swap disabled |
| Rancher Desktop | moby engine (Docker-compatible), Kubernetes enabled |
| WezTerm | JetBrains Mono Nerd Font, One Half Dark scheme, bar cursor, bell off; opens Ubuntu by default; Ctrl+Shift+1/2/3 switch cmd / pwsh (D:\code) / Ubuntu |
| PowerShell prompt | Starship (nerd-font-symbols preset) for PS5 and PS7 |
| PowerShell UX | fzf + PSFzf (Ctrl+T / Ctrl+R), PSReadLine predictive IntelliSense (ListView) |
| Package caches | npm + NuGet caches relocated onto the `D:` Dev Drive (per-user env vars) |
| System | Long path support, OpenSSH Agent, Defender exclusion for WSL vhdx |
| Git | autocrlf, defaultBranch, pull.rebase, push.autoSetupRemote |

### 2. Ubuntu / WSL

Inside your WSL Ubuntu terminal:

```bash
bash setup-ubuntu.sh
```

Git name/email auto-detect from the logged-in Windows (Entra) user — email from
the UPN (`whoami.exe /upn`), name from the Windows logon display name. Override
by exporting them first, or set `AUTO_DETECT_GIT_IDENTITY=false` to disable:

```bash
export GIT_NAME="Your Name"
export GIT_EMAIL="your@email.com"
bash setup-ubuntu.sh
```

Installs and configures:

| Category | What gets set up |
|---|---|
| Shell | zsh (set as default), Starship, fzf, zoxide, zsh-autosuggestions + zsh-syntax-highlighting |
| Dev tools | git, build-essential, ripgrep, fd, bat, eza, jq, wget, zip, git-delta, lazygit, GitHub CLI, Node.js |
| Languages | .NET SDK, Python (venv/pip/pipx/uv) |
| Kubernetes | kubectl, helm, k9s, kubectx, kubens, stern |
| Containers | verifies Rancher Desktop's docker is wired into WSL |
| Git | user config (auto-detected from Windows), defaults, SSH commit signing |
| SSH | ed25519 key pair |
| System | /etc/wsl.conf (automount metadata, systemd) |

After the script finishes it prints your SSH public key and next steps.

## Customisation

Both scripts have a `PARAMETERS` section at the very top — edit values there before running. No changes to the implementation section are needed for common adjustments.

**Windows** — remove entries from `Fonts`, `CloudCLIs`, or `VSCodeExtensions`; change the `Starship.Preset` or the `WezTermConfig` appearance/`PwshStartDir`; override `WslConfig` memory/CPU values explicitly instead of auto-detecting; toggle `DevDrivePackageCaches` (or repoint `Root`) to control npm/NuGet cache relocation.

**Bootstrap** (`bootstrap-windows.ps1`) — edit the `DevDrive` block to change the drive `Letter`, `SizeGB` (VHDX max — expandable, so it only uses real disk as it fills), or `VhdxPath`; set `Create = $false` to reuse an existing `D:`. `Repo.Url` / `CloneRoot` control where the repo lands. These only apply if you clone the repo first and run the script locally — the `irm … | iex` one-liner runs the defaults.

**Ubuntu** — set `INSTALL_KUBECTL=false` to skip Kubernetes tools; toggle `INSTALL_DOTNET` / `INSTALL_PYTHON` (or pin `DOTNET_SDK_VERSION`); set `GIT_SIGN_COMMITS=false` to skip SSH commit signing; change `STARSHIP_PRESET` to any name from [starship.rs/presets](https://starship.rs/presets/) (or empty for the built-in default); set `WSL_ENABLE_SYSTEMD=false` on older Windows builds.

## Keeping up to date

Two maintenance scripts refresh an already-provisioned machine — they install
nothing new, only upgrade what's there. Safe to rerun anytime.

```powershell
# Windows — as Administrator: OS updates, Defender defs, Store apps, WSL,
# winget upgrade --all, global npm packages
.\update-windows.ps1
```

```bash
# Ubuntu / WSL: apt upgrade + starship, zoxide, git-delta, lazygit, stern,
# k9s, kubectx, npm globals, pipx tools. Use --skip-<tool> to opt out.
bash update-ubuntu.sh
```

Toggle individual steps in each script's `PARAMETERS` block (or via `--skip-*`
flags / env vars on Ubuntu).

## System requirements

| | Minimum |
|---|---|
| Windows | Windows 10/11 (Home, Pro, or Enterprise) |
| RAM | 16 GB recommended (scripts allocate 75% to WSL) |
| Dev Drive | ReFS Dev Drive at `D:` needs Windows 11 22H2 (build 22621.2338+); older builds fall back to an NTFS volume automatically |
| WSL networking | `networkingMode=mirrored` requires Windows 11 22H2+ |
| Systemd in WSL | Requires Windows 11 22H2+ / WSL 2.0 |

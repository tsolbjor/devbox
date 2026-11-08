# Windows setup

Covers `bootstrap-windows.ps1` and `setup-windows.ps1`. For the short version, see
the [Quick Start](../README.md#quick-start).

## Prerequisites

- Windows 10/11 with WSL support
- [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/) (App Installer from the Microsoft Store)
- PowerShell run as Administrator

## Bootstrap a blank PC

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

## What gets installed and configured

| Category | What gets set up |
|---|---|
| Apps | WezTerm, PowerShell 7, VS Code, Git, Rancher Desktop, PowerToys, 7-Zip, Node.js via fnm (host), Azure Functions Core Tools, Aspire CLI |
| CLI tools | ripgrep, bat, fd, jq, yq, sops, git-delta, lazygit, glow, yazi, micro, GitHub CLI — the same basics `setup-ubuntu.sh` installs, so pwsh matches the WSL shell |
| Agentic CLIs | Claude Code (native install, self-updating), Codex (winget) |
| Fonts | Cascadia Code, JetBrains Mono Nerd Font |
| Cloud CLIs | Azure CLI, Azure Developer CLI (`azd`), kubelogin (Entra auth for AKS) — add AWS CLI / Google Cloud SDK via `CloudCLIs` |
| VS Code | Remote WSL, Dev Containers, Docker extensions |
| WSL | Ubuntu distro, resource limits (75% RAM/CPU), mirrored networking, swap disabled when allocated RAM ≥ 16 GB |
| Rancher Desktop | moby engine (Docker-compatible), Kubernetes enabled |
| WezTerm | JetBrains Mono Nerd Font, One Half Dark scheme, bar cursor, bell off; opens Ubuntu by default; local panes run pwsh (not cmd); Ctrl+Shift+1/2 switch pwsh (D:\code) / Ubuntu; Ctrl+Shift+3 opens a dev-layout tab (Claude Code \| yazi / shell) in the current directory; Ctrl+Shift+Alt+arrows split in any direction, inheriting the pane's shell and directory |
| PowerShell prompt | Starship (nerd-font-symbols preset) for PS5 and PS7 |
| PowerShell UX | fzf + PSFzf (Ctrl+T / Ctrl+R), PSReadLine predictive IntelliSense (ListView) |
| Package caches | npm + NuGet caches relocated onto the `D:` Dev Drive (per-user env vars) |
| System | Long path support, OpenSSH Agent, Defender exclusion for WSL vhdx |
| Git | identity (auto-detected from the Entra user unless already set), autocrlf, defaultBranch, pull.rebase, push.autoSetupRemote, delta as the diff pager |

Keyboard shortcuts and how-tos for WezTerm, Starship and the CLI tools are in the
[terminal cheatsheet](cheatsheet.md).

## Customisation

Each script has a `PARAMETERS` section at the very top — edit values there before
running. No changes to the implementation section are needed for common adjustments.

**`setup-windows.ps1`** — remove entries from `Fonts`, `CloudCLIs`, or
`VSCodeExtensions`; change the `Starship.Preset` or the `WezTermConfig`
appearance/`PwshStartDir`; override `WslConfig` memory/CPU values explicitly
instead of auto-detecting; toggle `DevDrivePackageCaches` (or repoint `Root`) to
control npm/NuGet cache relocation.

**`bootstrap-windows.ps1`** — edit the `DevDrive` block to change the drive
`Letter`, `SizeGB` (VHDX max — expandable, so it only uses real disk as it fills),
or `VhdxPath`; set `Create = $false` to reuse an existing `D:`. `Repo.Url` /
`CloneRoot` control where the repo lands. These only apply if you clone the repo
first and run the script locally — the `irm … | iex` one-liner runs the defaults.

## System requirements

| | Minimum |
|---|---|
| Windows | Windows 10/11 (Home, Pro, or Enterprise) |
| RAM | 16 GB recommended (scripts allocate 75% to WSL) |
| Dev Drive | ReFS Dev Drive at `D:` needs Windows 11 22H2 (build 22621.2338+); older builds fall back to an NTFS volume automatically |
| WSL networking | `networkingMode=mirrored` requires Windows 11 22H2+ |
| Systemd in WSL | Requires Windows 11 22H2+ / WSL 2.0 |

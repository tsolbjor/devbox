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
enables Windows `sudo`, and clones this repo to `D:\code\devbox`. It installs no
apps and doesn't touch WSL — it just prepares the ground, then prints the next
command.

From an elevated **cmd** prompt instead:

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/tsolbjor/devbox/main/bootstrap-windows.ps1 | iex"
```

Then run the full setup from the cloned folder:

```powershell
Set-Location D:\code\devbox
.\setup-windows.ps1
```

## Running elevated with sudo

Windows 11 24H2 and later include their own `sudo`. Bootstrap and setup switch it
on in its default *new window* mode (`SudoMode` in `$Config`; a mode you already
picked is kept). After that, you don't need a "Run as administrator" window to run
setup or update again. From any normal terminal:

```powershell
sudo powershell -NoProfile -ExecutionPolicy Bypass -File D:\code\devbox\update-windows.ps1
sudo powershell -NoProfile -ExecutionPolicy Bypass -File D:\code\devbox\setup-windows.ps1
```

`-ExecutionPolicy Bypass` goes on the command because the elevated PowerShell is a
new process: a `Set-ExecutionPolicy -Scope Process` in your own window doesn't
reach it. In new-window mode the scripts wait for Enter before the window closes.
For output in the same terminal, switch to inline mode once with
`sudo config --enable normal` (from an elevated prompt).

On a blank PC, sudo is still off until bootstrap has run, so the first step needs
the elevated window. An organisation policy can also block sudo. Bootstrap and
setup then print a ⚠ and carry on.

> Already have Git and a `D:` drive? Skip the bootstrap — clone the repo and run
> `.\setup-windows.ps1` directly.

## What gets installed and configured

| Category | What gets set up |
|---|---|
| Apps | WezTerm, PowerShell 7, VS Code, Git, Rancher Desktop, PowerToys, 1Password, 7-Zip, Node.js via fnm (host), Azure Functions Core Tools, Aspire CLI |
| CLI tools | ripgrep, bat, fd, jq, yq, sops, git-delta, lazygit, glow, yazi, micro, GitHub CLI, 1Password CLI (`op`) — the same basics `setup-ubuntu.sh` installs, so pwsh matches the WSL shell |
| Agentic CLIs | Claude Code (native install, self-updating), Codex (winget) |
| Fonts | JetBrains Mono Nerd Font (from its release zip; Cascadia Code ships with Windows) |
| Cloud CLIs | Azure CLI (extensions in one shared `AZURE_EXTENSION_DIR`), Azure Developer CLI (`azd`, signing in through az), kubelogin (Entra auth for AKS), k9s, kubectx, kubens, stern — add AWS CLI / Google Cloud SDK via `CloudCLIs`. kubectl and helm come with Rancher Desktop |
| Per-folder env | mise, activated in the PS5 and PS7 profiles: a client's `KUBECONFIG` and `AZURE_CONFIG_DIR` per folder (below) |
| VS Code | Remote WSL, Dev Containers, Docker extensions |
| WSL | Ubuntu distro, resource limits (75% RAM/CPU), mirrored networking, swap disabled when allocated RAM ≥ 16 GB |
| Rancher Desktop | moby engine (Docker-compatible), Kubernetes enabled. Its memory and CPUs are the WSL VM's, set in `.wslconfig` |
| WezTerm | JetBrains Mono Nerd Font, One Half Dark scheme, bar cursor, bell off; opens Ubuntu by default; local panes run pwsh (not cmd); Ctrl+Shift+1/2 switch pwsh (D:\code) / Ubuntu; Ctrl+Shift+3 opens a dev-layout tab (Claude Code \| yazi / shell) in the current directory; Ctrl+Shift+Alt+arrows split in any direction, inheriting the pane's shell and directory |
| PowerShell prompt | Starship (nerd-font-symbols preset) for PS5 and PS7 |
| PowerShell UX | fzf + PSFzf (Ctrl+T / Ctrl+R), PSReadLine predictive IntelliSense (ListView) |
| Package caches | npm + NuGet caches relocated onto the `D:` Dev Drive (per-user env vars) |
| System | Long path support, OpenSSH Agent, Windows `sudo` (enabled when off), Defender exclusion for every registered WSL distro's vhdx folder and Rancher Desktop's data |
| Git | identity (auto-detected from the Entra user unless already set), autocrlf, defaultBranch, pull.rebase, push.autoSetupRemote, delta as the diff pager |

Keyboard shortcuts and how-tos for WezTerm, Starship and the CLI tools are in the
[terminal cheatsheet](cheatsheet.md).

## A kubeconfig and az login per folder

This is the same convention as the WSL shell ([ubuntu.md](ubuntu.md#a-kubeconfig-and-az-login-per-folder)).
A trusted `mise.toml` above a client's repos sets `KUBECONFIG` and
`AZURE_CONFIG_DIR` while you are inside that folder:

```powershell
New-Item -ItemType Directory -Force "$HOME\.kube\clients" | Out-Null
@'
[env]
KUBECONFIG       = "{{env.USERPROFILE}}/.kube/clients/acme.yaml"
AZURE_CONFIG_DIR = "{{env.USERPROFILE}}/.azure-clients/acme"
'@ | Set-Content D:\code\acme\mise.toml
mise trust D:\code\acme      # once, and again whenever the file changes

Set-Location D:\code\acme\some-repo
az login --tenant <tenant>
az aks get-credentials -g <rg> -n <cluster> --file $env:KUBECONFIG
kubelogin convert-kubeconfig -l azurecli
k9s
```

Write `{{env.USERPROFILE}}`: Windows has no `HOME` variable, and mise does not
expand `~`. Windows and WSL keep separate files, so a client you use from both has
a `mise.toml` and a login on each side.

mise wraps the prompt function, so its profile block must stay below the Starship
line. Setup warns and the audit reports drift if it doesn't. In Windows PowerShell
5.1 the folder's env applies at the next prompt; pwsh 7 applies it on `cd`. Either
way mise prints the variables that changed (`mise +AZURE_CONFIG_DIR +KUBECONFIG`,
names only); `mise env` shows their values.

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

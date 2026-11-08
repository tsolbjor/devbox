# devbox

Automated, idempotent setup scripts for a Windows + WSL2 development environment.
The Ubuntu scripts also run on a standalone (native) Ubuntu machine.

> 📄 **New here?** See the [**terminal cheatsheet**](docs/cheatsheet.md) for WezTerm, Starship,
> and CLI-addon keyboard shortcuts and how-tos.

## Quick Start

### 1. Windows

On a blank PC (no Git, no `D:` drive yet), open **PowerShell as Administrator**:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
irm https://raw.githubusercontent.com/tsolbjor/devbox/main/bootstrap-windows.ps1 | iex
```

This installs Git, creates a Dev Drive at `D:` and clones this repo to
`D:\code\devbox`. Then run the full setup:

```powershell
Set-Location D:\code\devbox
.\setup-windows.ps1
```

Details, what gets installed and how to customise it: [docs/windows.md](docs/windows.md).

### 2. Ubuntu (WSL or native)

Inside your Ubuntu terminal:

```bash
bash setup-ubuntu.sh
```

On WSL, Git name/email auto-detect from the Windows (Entra) user; on a fresh native
machine export `GIT_NAME` / `GIT_EMAIL` first. Details: [docs/ubuntu.md](docs/ubuntu.md).

### 3. Keep it current

```powershell
.\update-windows.ps1    # as Administrator
.\audit-windows.ps1     # read-only drift report
```

```bash
bash update-ubuntu.sh
bash audit-ubuntu.sh
```

Every script is safe to rerun. Updates, drift reports, version pins and ignore
lists: [docs/maintenance.md](docs/maintenance.md).

## Documentation

| | |
|---|---|
| [docs/windows.md](docs/windows.md) | Windows bootstrap and setup: what gets installed, customisation, requirements |
| [docs/ubuntu.md](docs/ubuntu.md) | Ubuntu / WSL setup, WSL vs native, a kubeconfig per folder |
| [docs/maintenance.md](docs/maintenance.md) | Update scripts, drift audits, version pins |
| [docs/cheatsheet.md](docs/cheatsheet.md) | Terminal keyboard shortcuts and how-tos |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | Working on the scripts: conventions, testing |
| [docs/adr/](docs/adr/) | Architecture decision records — why things are the way they are |
| [docs/plans/](docs/plans/) | Planned work that is not implemented yet |

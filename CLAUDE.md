# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Idempotent setup scripts for a Windows + WSL2 development environment. There are no build steps, tests, or CI pipelines — the scripts *are* the product.

## Scripts

| File | Language | Run as | Purpose |
|------|----------|--------|---------|
| `bootstrap-windows.ps1` | PowerShell | Administrator | First-run bootstrap for a blank PC: verifies winget, installs Git, creates a VHDX-backed Dev Drive at `D:` (with a boot-time re-attach task), clones this repo to `D:\code\devbox`. Installs no apps; prepares the ground for `setup-windows.ps1`. Fetch-and-run via `irm .../bootstrap-windows.ps1 | iex` |
| `setup-windows.ps1` | PowerShell | Administrator | Installs WezTerm, PowerShell 7, VS Code, Git, Rancher Desktop, PowerToys, 7-Zip, host Node via fnm (`Ensure-Node` — `NodeMajorVersion` default, a managed `fnm` profile block, npm globals in a shared `%APPDATA%\npm` prefix; `MigrateLegacyNode` = ask|yes|no offers to carry nvm-windows globals over and uninstall nvm-windows / the Node MSI), Azure Functions Core Tools, Azure CLI, `azd`, kubelogin, Aspire CLI, Codex, and the `CliTools` set (ripgrep/bat/fd/jq/delta/lazygit/glow/gh — pwsh parity with the WSL shell, installed *before* the Git block because `Ensure-WindowsGitConfig` wires delta in as the pager); installs Claude Code from Anthropic's own installer rather than winget (`Ensure-ClaudeCode` — the only app here outside the winget inventory, because the native build self-updates in the background and the winget one cannot replace a running `claude.exe`; it also uninstalls a winget copy left by an earlier run); writes a managed `~/.wezterm.lua`, configures the Starship prompt, and writes `~/.wslconfig` with 75% of system RAM/CPUs; configures Rancher Desktop VM (moby engine, Kubernetes enabled); relocates npm/NuGet caches onto the `D:` Dev Drive. Sets the Git identity (`Ensure-GitIdentity` — keeps an existing one, else detects it from the Entra UPN / logon display name). A failed winget install is collected and fails the run at the end: `$ErrorActionPreference = "Stop"` never sees a native exit code, so `Install-WingetPackage` checks `$LASTEXITCODE` itself |
| `setup-ubuntu.sh` | Bash | Normal user | Installs apt packages plus Node via fnm and the npm-global CLIs (`ncu`, Codex) via `ensure_node` — fnm, not apt, so client repos can pin their own Node (`.nvmrc`/`.node-version`, switched on `cd` by the managed `devbox: fnm` rc block); `NODE_MAJOR_VERSION` is only the default, and globals go to `NPM_GLOBAL_PREFIX` (`~/.local`), shared by every Node version, because fnm otherwise gives each version its own and globals vanish on every patch bump. `migrate_legacy_node` moves an older machine off apt `nodejs`/NodeSource/nvm — reinstalling old root-owned globals under fnm first, backing up rc files before stripping nvm lines — asking before each step (`MIGRATE_LEGACY_NODE=ask|yes|no`; no terminal → skipped), Claude Code via its own installer (`ensure_claude_code` — self-updating, so no `update-ubuntu.sh` step; it also removes an earlier npm-global copy), kubelogin (`ensure_kubelogin` — the Entra credential plugin kubectl execs against an Entra-integrated AKS cluster), `azd` (`ensure_azd` — no shim needed, unlike aspire: its installer symlinks into `/usr/local/bin`, and it must run *without* sudo because the script elevates its own steps), the .NET SDK, .NET global tools (`ensure_dotnet_tools` — `dotnet-outdated`, shimmed from `~/.dotnet/tools` into `~/.local/bin` rather than adding another rc PATH line) and the Aspire CLI (`ensure_aspire` — upstream installer into `~/.aspire/bin` with `--skip-path`, plus a `~/.local/bin` shim, because the installer would otherwise write a PATH line to bash only), configures Git globally (on WSL also the Windows Git Credential Manager as HTTPS helper — `ensure_git_credential_manager`), merges `/etc/wsl.conf` key by key (`ini_set` — never wholesale, it holds the distro's `[user] default=`), generates SSH key, creates `~/code`. Shell stack: Starship is the *only* prompt engine; oh-my-zsh is installed as a framework only (`ZSH_THEME=""`) and loads zsh-autosuggestions/zsh-syntax-highlighting from `custom/plugins` git clones — the apt zsh-autosuggestions (0.7.0) stops drawing inline suggestions in this stack, so the apt packages are a fallback only. Each plugin loads exactly once, via omz or apt, never both. `ensure_shell_history` writes the history/prediction blocks (the zsh counterpart of the Windows PSReadLine block) — see *Managed blocks* below |
| `update-windows.ps1` | PowerShell | Administrator | Maintenance-only refresh of an existing machine: OS/Defender/Store updates, `wsl --update`, `winget upgrade --all` (which updates fnm), latest patch of the fnm default Node major (`Update-Node`, pruning the replaced patch), global npm packages. Installs nothing new |
| `update-ubuntu.sh` | Bash | Normal user | Maintenance-only refresh: apt upgrade plus fnm and the latest patch of its default Node major (`update_node` — prunes the replaced patch, never moves the major), starship, zoxide, git-delta, lazygit, stern, glow, aspire, k9s, kubectx, kubelogin, azd, npm globals, pipx tools, .NET global tools (walked one by one — the SDK has no `dotnet tool update --all`). `--skip-*` flags opt out. `--pins` adds an opt-in, per-item-confirmed reconcile that moves node/kubectl to the versions pinned in `setup-ubuntu.sh` (kubectl: rewrites the apt source and replaces the minor; node: installs the pinned major alongside and makes it the fnm default — hence off by default and never part of a routine refresh); `--pins-yes` answers yes to all, and a run with no terminal skips rather than hangs |
| `audit-windows.ps1` | PowerShell | Normal user | Read-only drift report: winget apps / VS Code extensions / npm globals not in (or missing from) setup, plus natively-installed apps that the winget inventory cannot see (Claude Code — flags a non-native `claude.exe` winning the PATH race), plus a Node (fnm) section (fnm default vs `NodeMajorVersion`, the npm prefix, a leftover Node MSI / nvm-windows, a non-fnm `node.exe` on PATH), plus managed-config drift (WezTerm, PS profiles incl. the `fnm` block, `.wslconfig`, cache env vars, Git), plus startup & services (verifies the `DevboxMountDevDrive` task and `ssh-agent` StartupType, then inventories non-Microsoft autostart: logon/boot tasks, Run keys, Startup folder, third-party auto services). Extras are filtered through `$Config.Ignore` (exact ids per category plus `Patterns` regexes, pre-seeded with the VC++/WindowsAppRuntime/UI.Xaml runtimes) — the third answer to a finding that is neither drift nor setup-worthy; `-Triage` fills it via a checkbox picker. Prints two-way reconcile hints |
| `audit-ubuntu.sh` | Bash | Normal user | Read-only drift report: expected CLIs, managed rc blocks (presence, duplication, and — for the two order-sensitive zsh history blocks — *position*), effective `HISTSIZE`/`SAVEHIST` against `SHELL_HISTORY_SIZE`, the inline-suggestion colour (flags the invisible stock `fg=8`), `starship.toml`, `/etc/wsl.conf`, Git, default shell, oh-my-zsh (present, sourced, `ZSH_THEME` empty, no plugins loaded twice), plus extra snap/pipx/npm/dotnet-global apps, plus startup & services (systemd running-state, then inventories units enabled against their vendor preset and user crontab), plus a docker-engine check (flags shadow apt/snap dockerds fighting Rancher Desktop for the socket, and verifies the CLI + answering daemon are Rancher's). Also compares the installed node/kubectl/dotnet versions against the pins parsed out of `setup-ubuntu.sh` (for node, the fnm default; a separate *Node toolchain* section flags anything else providing node — apt `nodejs`, NodeSource, nvm rc lines, globals left in a root-owned prefix, an npm prefix that isn't `NPM_GLOBAL_PREFIX`, several node binaries on PATH — because the `node` that wins PATH can look fine while an off-pin copy hides behind it) — the one drift nothing else would report, because every `ensure_*` using those pins short-circuits on "command already present". Extras are filtered through the `IGNORE_*` lists at the top (space-separated; `IGNORE_PATTERNS` holds EREs) — the Windows `$Config.Ignore` counterpart, hand-edited: there is no `--triage` here yet. `--apt-extras` / `--local-bin` add noisier checks. Changes nothing; prints two-way reconcile hints |

All scripts are safe to rerun (idempotent). The `audit-*` scripts are additionally read-only — with one deliberate exception: `audit-windows.ps1 -Triage` rewrites `$Config.Ignore` **in `audit-windows.ps1` itself** (AST-located, so a value containing braces or quotes cannot derail the splice) and touches nothing else, leaving the change in git to review.

The audit scripts derive their "expected" state by parsing the setup scripts — `audit-windows.ps1` AST-extracts the `$Config` hashtable and regexes `-Id`/`npm install -g` calls out of `setup-windows.ps1`; `audit-ubuntu.sh` parses the `APT_PACKAGES` array plus `ensure_pkg`/`ensure_command` calls out of `setup-ubuntu.sh`. Keep that parsing in sync when the setup scripts change shape (e.g. renaming `$Config` keys or the package array).

## Version pins

Three pins in `setup-ubuntu.sh` track upstream support windows and go stale silently — nothing in the scripts warns when one ages out, so check them whenever you review the stack:

| Pin | Reviewed | Upstream |
|---|---|---|
| `DOTNET_SDK_VERSION` | 2026-09-24 → `10.0` | LTS every even November, 3 years of support. 8.0 leaves support 2026-11-10 |
| `KUBECTL_VERSION` | 2026-09-24 → `v1.37` | Only the newest three minors get patches; kubectl must stay within one minor of the cluster |
| `NODE_MAJOR_VERSION` | 2026-09-24 → `24` | Even majors go LTS each October; 22 reached EOL 2026-09-23. The fnm *default* only — projects pin their own. Mirrored by `NodeMajorVersion` in `setup-windows.ps1` |

Everything else floats: winget and apt packages follow their feeds, and the GitHub-release installers (`ensure_stern`, `ensure_kubectx`, `ensure_kubelogin`, …) resolve `latest` at run time — through `gh_latest_tag` / `get_github_latest_tag`, which authenticate with `GITHUB_TOKEN` or `gh auth token` when available (the anonymous 60 calls/hour is shared behind a corporate NAT) and fail loudly on an empty tag. In `update-ubuntu.sh` every caller needs `|| return 1`: `run_step` runs steps as an `if` condition, which suspends `set -e`.

Reruns never silently move what an existing machine runs, so the pins are reconciled differently:

- **dotnet** SDKs install side by side, so `ensure_dotnet` keys on the *pinned* SDK rather than on `dotnet` existing at all. A plain `bash setup-ubuntu.sh` adds the new one and removes nothing.
- **node** versions also sit side by side under fnm, so a setup rerun installs the pinned major — but leaves the fnm *default* where it is and only warns, since moving it changes every shell outside a pinned project. `bash update-ubuntu.sh --pins` moves it, asking first.
- **kubectl** replaces the installed minor, so `ensure_kubectl` stays guarded on "command already present". `bash update-ubuntu.sh --pins` reconciles it, asking first.
- `audit-ubuntu.sh` reports all three, so a stale pin cannot sit unnoticed.

## Running the scripts

```powershell
# Windows — must be run as Administrator
.\setup-windows.ps1
```

```bash
# Ubuntu/WSL — GIT_NAME/GIT_EMAIL auto-detect from the Windows (Entra) user on WSL
# (UPN + logon display name); export them to override, or set
# AUTO_DETECT_GIT_IDENTITY=false to disable. Still required if detection finds nothing.
bash setup-ubuntu.sh
```

## Coding conventions

### All scripts
- All user-configurable values live at the top in a clearly marked `PARAMETERS` section. Core logic stays untouched when users customise.
- Status output uses `✓` (already done), `→` (taking action), `⚠` (warning).

### Bash (`setup-ubuntu.sh`, `update-ubuntu.sh`)
- Strict mode: `set -euo pipefail`
- Functions: `snake_case` verbs — `ensure_pkg`, `ensure_dir`, `ensure_git_config`, `ensure_ssh_key`, `ensure_command`
- Variables: `UPPER_CASE` for env/config, `lower_case` locals

### PowerShell (`setup-windows.ps1`, `bootstrap-windows.ps1`, `update-windows.ps1`)
- Strict mode: `Set-StrictMode -Version Latest`, `$ErrorActionPreference = "Stop"`
- Functions: `PascalCase` verb-noun — `Ensure-WSL`, `Install-WingetPackage`, `Get-SystemResources`
- Config: top-level `$Config` hashtable; `$null` values are resolved at runtime (e.g. WSL memory auto-detects to 75% of system RAM via `Get-SystemResources` + `Get-WslAllocation`)
- Rancher Desktop settings are merged into its existing `settings.json` — never wholesale replaced

### Idempotency pattern
Check current state, skip if already correct, act and report if not. Every `Ensure-*` / `ensure_*` function follows this pattern.

Managed blocks written into user config (PowerShell profiles, rc files) are delimited by `# --- devbox: <marker> ... # --- end devbox block ---` and rewritten **in place** by `Set-ManagedProfileBlock` (PowerShell) / `set_managed_block` (Bash), not merely appended when the marker is absent. Marker-presence-only checks strand every existing machine on the old block the moment the snippet changes. `audit-windows.ps1` cross-checks the installed block against the here-string it parses out of the setup function, so a stale block reports as drift.

The older Ubuntu block `devbox terminal cwd` predates this and still uses a bare marker with append-if-absent. `devbox eza aliases` used to as well; `migrate_legacy_eza_block` wraps it in the managed delimiters where it sits. New Bash blocks should use `set_managed_block`.

**Load order is part of the contract for the zsh history blocks.** `devbox: zsh history` must sit *above* the oh-my-zsh source line (omz's `lib/history.zsh` reassigns `HISTSIZE`/`SAVEHIST`, and zsh-autosuggestions only honours `ZSH_AUTOSUGGEST_*` already set when it loads); `devbox: zsh history keys` must sit *below* the fzf integration (fzf binds `^I`). Hence `ensure_shell_history` runs after `ensure_omz`/`ensure_fzf_shell_integration`, splices with `insert_before_anchor` on first write, and rewrites in place afterwards so the position survives. `audit-ubuntu.sh` compares line numbers rather than trusting marker presence — a block in the wrong place fails silently otherwise.

Two traps worth remembering, both of which produced silent no-ops here: awk turns the `\$` of an anchor like `\$ZSH/oh-my-zsh.sh` into a bare `$` (end-of-line in ERE, matches nothing), so `insert_before_anchor` matches with `index()` on a literal instead; and `grep -c` already prints `0` on no match, so a trailing `|| echo 0` yields `"0\n0"` and breaks every `[[ -eq ]]` downstream.

## DevContainer

`.devcontainer/` defines an Ubuntu 22.04 container used when developing inside this repo via VS Code. Git identity is injected via `containerEnv` in `devcontainer.json` — edit those values to personalise.

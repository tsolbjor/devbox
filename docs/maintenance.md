# Keeping a machine current

Once a machine is set up, two kinds of script look after it: the `update-*`
scripts refresh what is installed, and the `audit-*` scripts report where the
machine has drifted from what setup would produce.

## Keeping up to date

Two maintenance scripts refresh an already-provisioned machine — they install
nothing new, only upgrade what's there. Safe to rerun anytime.

```powershell
# Windows — as Administrator: OS updates, Defender defs, Store apps, WSL,
# winget upgrade --all, latest Node patch (fnm), global npm packages
.\update-windows.ps1
```

```bash
# Ubuntu (WSL or native): apt upgrade + fnm and the latest Node patch, starship, zoxide,
# git-delta, lazygit, stern, glow, yq, sops, yazi, k9s, kubectx, the .NET SDKs (newest feature band per major),
# npm globals, pipx tools. Use --skip-<tool> to opt out.
bash update-ubuntu.sh
```

Toggle individual steps in each script's `PARAMETERS` block (or via `--skip-*`
flags / env vars on Ubuntu).

**Per-user winget installs** (Aspire CLI, devtunnel, …) cannot be upgraded from
an elevated session, so `update-windows.ps1` upgrades each one again as you,
without elevation, through a one-off scheduled task it removes afterwards. If
that cannot run (the elevated account is not the one signed in), it prints the
`winget upgrade --id <id> -e` to run from a normal terminal.

One thing `update-windows.ps1` reports with `⚠` but does not do itself:

- **npm install scripts.** npm runs no install script that `allow-scripts` does
  not allow, so a global whose postinstall fetches a binary
  (azure-functions-core-tools, esbuild) is left with the old one or none. The run
  names the skipped packages and the globals that pull them in, and prints the
  `npm install -g --allow-scripts=…` that reinstalls them. Allowing them is a
  trust decision, so the script does not make it for you.

## Detecting drift

Over time a machine accumulates apps and config the setup process doesn't know
about. The `audit-*` scripts report that drift — **read-only, they change
nothing** (bar `audit-windows.ps1 -Triage`, which edits only its own ignore
list) — and derive "expected" state by parsing the setup scripts themselves,
so they can't fall out of sync with what setup actually does.

```powershell
# Windows: winget apps / VS Code extensions / npm globals not in (or missing
# from) setup, .NET SDKs left behind, plus managed-config drift (WezTerm,
# PowerShell profiles, .wslconfig, cache env vars, Git)
.\audit-windows.ps1
```

```bash
# Ubuntu (WSL or native): expected CLIs, managed rc blocks, starship.toml, /etc/wsl.conf (WSL),
# Git, default shell, version pins, plus extra snap/pipx/npm/dotnet apps
bash audit-ubuntu.sh              # add --apt-extras / --local-bin for noisier checks
```

Setup installs no .NET on Windows, but winget's `Microsoft.DotNet.SDK.<major>`
packages and Visual Studio do, and neither removes anything: each new feature
band installs next to the old one, and a major stays after it leaves support.
The audit's *.NET SDKs* section reports every SDK that a newer one of the same
major replaces, and every SDK and runtime of an out-of-support major (according
to Microsoft's release index, the source `dotnet sdk check` uses), each with its
`winget uninstall --id Microsoft.DotNet.SDK.<major> --version <v>` line. Before
removing an older band, check that no repo's `global.json` pins it with the
default `rollForward: latestPatch`. On Ubuntu, `update-ubuntu.sh` already prunes
replaced patches in `~/.dotnet`.

Each finding prints a two-way reconcile hint: how to **fix** the drift (rerun
setup, install/uninstall) and, for unexpected apps, how to **adopt** it into
setup (add to a `$Config` array / `APT_PACKAGES` / an `ensure_*` step) — so the
report doubles as a worklist for updating the setup scripts.

## Version pins

`setup-ubuntu.sh` pins the .NET SDK, kubectl and Node major versions. A rerun
never swaps what an existing machine runs out from under you; the audit reports
the gap, and reconciling it is an explicit step
([ADR 0011](adr/0011-reconcile-version-pins-explicitly.md)):

```bash
bash update-ubuntu.sh --pins      # asks before each; --pins-yes to accept all
```

- **.NET** needs no flag: SDKs install side by side, so a plain
  `bash setup-ubuntu.sh` adds the pinned SDK and leaves the old one in place.
- **Node** comes from [fnm](https://github.com/Schniz/fnm), and the pin is only
  its *default* — a project's `.nvmrc` / `.node-version` wins inside that
  directory. A setup rerun installs the pinned major alongside; `--pins` makes it
  the default. npm globals live in `~/.local` (`%APPDATA%\npm` on Windows),
  shared by every Node version, so they survive both.
- **kubectl** replaces the installed minor, so only `--pins` moves it.

## Silencing what is neither

Most machines carry software that is neither drift nor setup-worthy — 1Password,
Office, a browser, the runtime redistributables other installers drag in. There
is no honest `fix:` or `adopt:` for those, and left unanswered they bury the
findings that matter. Both audits take an ignore list for exactly that third
answer, and Windows can fill it interactively:

```powershell
.\audit-windows.ps1 -Triage
```

This walks each category of *Extra* finding through a checkbox picker (`↑`/`↓`,
`Space` to tick, `A`/`N` for all/none, `Enter` to confirm, `Esc` to skip) and
folds what you ticked into `$Config.Ignore` in `audit-windows.ps1` itself. It is
the one mode that writes anything — and only to that file, so the change lands in
git where you can read it before committing. Nothing on the machine is touched.

`$Config.Ignore.Patterns` takes regexes for families that would otherwise need a
dozen literal entries each; it ships pre-seeded with the VC++ / WindowsAppRuntime
/ UI.Xaml runtimes. On Ubuntu the same lists are the `IGNORE_*` variables at the
top of `audit-ubuntu.sh` (space-separated; `IGNORE_PATTERNS` holds regexes),
edited by hand — there is no `--triage` there yet.

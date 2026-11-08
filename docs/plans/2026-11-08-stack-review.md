# Stack review — 2026-11-08

- **Status:** Open
- **Scope:** implementation, overall approach, and tool selection across Windows, WSL and
  native Ubuntu
- **Follows:** the 2026-09-26 review. Its steps 1–3 (quick fixes, CI, generated shell
  config) are done; its open items are folded in below.

## Summary

The idea is sound and well executed. Every script is safe to rerun, there is a
read-only audit, the shell config is generated as a pure function you can diff
([ADR 0003](../adr/0003-generated-shell-config.md)), and CI runs setup twice and checks
the second run changes nothing. Most of the weakness is in the approach, not in bugs:

- Every tool is built three times (setup, update, audit) in about 6,000 lines of
  hand-written installers.
- On Windows, one elevated script also owns per-user state.

Those two choices cause most of the findings below.

## 1. Approach

- [ ] **A1. Collapse setup, update and audit into one description of what should be installed (mise).**
  About 14 tools have an `ensure_X` in setup, an `update_X` in update, and parsing in
  the audit. Each one rebuilds the same release-asset URL by hand, and none checks a
  checksum (46 `curl` downloads, no verification). mise with its aqua backend would give:
  - checksum verification on downloads;
  - one `mise upgrade` instead of ~20 update functions;
  - per-repo version pins in `.mise.toml` for kubectl, tofu, helm and node. For a
    consultancy where each client pins different versions, this is the main gain.

  It would also remove the "a copy elsewhere on PATH hides the managed one" bugs
  (kubectl, and earlier kubelogin), because mise owns its own install directory. Keep
  apt for system packages, `dotnet-install.sh` for .NET, and the native installer for
  Claude Code. *Try it on a branch first, measure the lines removed, then write an ADR.*
- [ ] **A2. Turn update into setup with an upgrade mode, not a second script.** Setup's
  "installed, so skip" and update's "older, so replace" are two implementations of the
  same goal. If each `ensure_*` knew which version it wants (latest or pinned),
  `update-ubuntu.sh` would mostly disappear. The step count kept by hand in both scripts
  (`TOTAL_STEPS` plus a parallel list of `if`s) is the same kind of duplication.
  Largely solved by A1.
- [ ] **A3. On Windows, split the elevated part from the per-user part.**
  - Elevated: a WinGet Configuration file (`configuration.dsc.yaml`, run with
    `winget configure`) for machine-wide packages, WSL features, long paths, the Dev
    Drive and ssh-agent. `winget configure test` covers most of the app audit.
  - Not elevated: a `setup-windows-user.ps1` for profiles, WezTerm, git, environment
    variables, fnm, Claude and VS Code extensions.

  This fixes the admin-profile problem (W5) and the winget install-scope problem at
  the root. Shared helpers go into a dot-sourced `common.ps1`; bootstrap stays
  standalone because it runs as `irm | iex`.
- [ ] **A4. Run CI on a schedule, and run the update script in it.** Almost everything
  resolves `latest`, so breakage comes from upstream changes, not commits, and
  push-only CI won't see it.
  - Add a weekly `schedule:` trigger.
  - Run `update-ubuntu.sh` after setup in the container. It is never run in CI today,
    and its URL builders are separate code that can break quietly.
  - Check `DOTNET_SDK_VERSION`, `KUBECTL_VERSION` and `NODE_MAJOR_VERSION` against
    endoflife.date and fail when one leaves support
    ([ADR 0011](../adr/0011-reconcile-version-pins-explicitly.md) notes nothing warns today).
- [ ] **A5. Decide what the Windows host is for.** It has Aspire and Azure Functions
  Core Tools but no .NET SDK, so it's neither a full dev environment nor just a
  terminal into WSL. Recommendation: make it the terminal, browser and GUI apps, and
  move language toolchains to WSL. Otherwise, add the SDK. *Write an ADR either way.*

## 2. Bugs

### High

- [ ] **B1. No `.gitattributes`.** `bootstrap-windows.ps1:202` clones to
  `D:\code\devbox` with `autocrlf=true`. Running `bash /mnt/d/code/devbox/setup-ubuntu.sh`
  then fails with `$'\r': command not found`. Fix: `* text=auto eol=lf` (optionally
  `*.ps1 eol=crlf`), and say in the docs where to run the Ubuntu script from.
- [ ] **B2. The reboot pass hides failed installs.** `Ensure-WSL` calls `exit 0`
  (`setup-windows.ps1:556`) after the app installs but before the failed-installs
  summary at `:1646`. The run reports success. Fix: print the failures and exit
  non-zero before the reboot exit, or run `Ensure-WSL` first.
- [ ] **B3. The Windows audit always reports drift for the font.** `audit-windows.ps1:295`
  expects `NERD-Fonts.JetBrainsMono` from winget, but setup installs it from a zip
  (`setup-windows.ps1:1576-1588`). Fix: skip it in the audit, or check by font face.
- [ ] **B4. `update-ubuntu.sh` stops at the first failing step.** `run_step` calls
  `exit 1`, so one flaky GitHub lookup skips the rest of the refresh. Fix: record the
  failure, carry on, and exit non-zero at the end, as the Windows scripts do.
- [ ] **B5. kubectl is never installed on WSL** (from the 2026-11-02 notes).
  `ensure_kubectl` skips when any `kubectl` is on PATH, and Rancher Desktop's Windows
  copy under `/mnt/c/.../Rancher Desktop/.../linux/bin` always is. The audit then
  reports pin drift forever, and `update-ubuntu.sh --pins` can't fix it. Fix: ignore
  `/mnt/` copies in `ensure_kubectl`; have the audit point to setup when only Rancher's
  copy exists; have `--pins` skip with a message.

### Medium

- [ ] **B6. SSH has no agent on WSL, and the Windows agent isn't used by Git.**
  - On WSL the key has no passphrase (`setup-ubuntu.sh:331`) and is used for both
    login and signing.
  - On Windows, Git uses its bundled `ssh.exe`, which ignores the Windows OpenSSH agent
    setup enables, because no `core.sshCommand` is set. The comment at
    `setup-windows.ps1:160` also claims WSL forwarding that nothing does.
  - Options: add a passphrase and run a systemd user ssh-agent in WSL; or drop SSH for
    authentication, since GCM already handles HTTPS for GitHub and Azure DevOps, and
    keep the key only for signing. On Windows, set `core.sshCommand` or drop the agent step.
- [ ] **B7. `safe.directory ~/code` likely does nothing.** Git needs an exact repo path
  here, and `/*` wildcards only arrived in Git 2.46, newer than the 2.43 on 24.04.
  Repos on ext4 are owned by the user anyway. Remove it, or point it at `/mnt/d` paths.
- [ ] **B8. Some native commands aren't checked on Windows.** Examples: `wsl --update`,
  `winget upgrade --all`, `fnm default`/`fnm uninstall`, `npm update -g`
  (update-windows.ps1); `npm install -g`, `code --install-extension`, the Claude
  installer (setup-windows.ps1). Worst case (`setup-windows.ps1:1252-1254`):
  nvm-windows is uninstalled even when moving its global packages failed. Fix: one
  `Invoke-Native` helper that throws on a non-zero `$LASTEXITCODE`.
- [ ] **B9. Windows PowerShell 5.1 writes a BOM into generated files.**
  `Set-Content -Encoding UTF8` puts one into `.wslconfig` (`:589`) and Rancher Desktop's
  `settings.json` (`:1065`). Whether those programs reject it is unverified. Fix:
  `[IO.File]::WriteAllText(..., [Text.UTF8Encoding]::new($false))`.
- [ ] **B10. `2>$null` on native commands under `Stop` can throw on 5.1.**
  `setup-windows.ps1:264, :531, :1003, :1104`; `audit-windows.ps1:298, :370, :458`.
  Unverified which of those commands actually write to stderr.
- [ ] **B11. The Dev Drive can't recover from a half-finished first run.** If the VHDX
  was created but formatting or the letter assignment failed, a rerun only mounts it
  (`bootstrap-windows.ps1:107-111`). Bootstrap also skips creation if anything at all is
  at `D:` (`:102`). Fix: after attaching, check the partition, filesystem and letter,
  and check `(Get-Volume D).FileSystemType -eq 'ReFS'` before skipping.
- [ ] **B12. `-Triage` puts personal ignores into the shared script.** One person's
  apps get committed into `audit-windows.ps1` for everyone, and the splice wipes the
  comments inside `Ignore`. Fix: a gitignored `audit-windows.local.psd1`.
- [ ] **B13. The Starship profile line isn't guarded** (`setup-windows.ps1:639-645`).
  If the Starship install failed, every new pwsh shell errors. Fix: wrap it in a guarded
  managed block.

### Carried over from the 2026-09-26 review

- [ ] **W1.** `.wslconfig` is written whole, not merged, and has no `autoMemoryReclaim`
  or `sparseVhd` (`setup-windows.ps1:562-594`).
- [ ] **W2.** The Rancher Desktop `virtualMachine.memoryInGB` / `numberCPUs` merge
  likely does nothing with the WSL backend (`:1033-1043`). Verify, and consider `rdctl set`.
- [ ] **W3.** `core.autocrlf=true` on Windows breaks shell scripts built into
  containers from `D:\code` (`:22`, `:1348`). Mostly fixed by B1 for repos with a
  `.gitattributes`; consider `input` as the Windows default.
- [ ] **W4.** PSWindowsUpdate (update-windows.ps1:64-90) and the Defender exclusions
  (setup-windows.ps1:1481-1517) may conflict with Intune policy on managed PCs.
- [ ] **W5.** An elevated run writes per-user config into the admin's profile when
  elevation uses a separate admin account. winget installs pass no `--scope`, so
  user-scope installers such as VS Code land there too. Fixed by A3.
- [ ] **W6.** The kubectl pin `v1.37` vs the AKS versions actually in use: check
  `az aks get-versions` for the client clusters.
- [ ] **W7.** The devcontainer is on Ubuntu 22.04, and docs/ubuntu.md says 20.04+,
  while the target is 24.04.
- [ ] **W8.** CLAUDE.md's script table has grown into paragraph-length cells that are
  hard to keep accurate. Move the reasoning to ADRs and keep the table short.

### Low

- [ ] The window-pause check may fire in a normal terminal too (unverified):
  `GetConsoleProcessList` returns 1 when the script runs in the session's own process.
  Setup also ends without `exit 0`, so a stale `$LASTEXITCODE` can leak.
- [ ] `wsl --install -d … | Out-Null` (`:537`) may hide the UNIX-username prompt; use
  `--no-launch`. `Test-Command wsl` is always true on Windows 11 (inbox stub).
- [ ] The Defender exclusion covers only `CanonicalGroupLimited*\LocalState`; newer
  distros live under `%LOCALAPPDATA%\wsl\{guid}` (unverified).
- [ ] Adding the npm prefix to the user PATH (`:1213`) stores it expanded as `REG_SZ`,
  flattening `%VAR%` entries.
- [ ] The PATH refresh is copy-pasted six times and drops the fnm multishell entry.
- [ ] Bootstrap's `git clone` exit code is unchecked (`bootstrap-windows.ps1:202`).
- [ ] The `irm | iex` bootstrap runs from mutable `main` as admin; pin a tag or commit.
  The Nerd Font zip and `claude.ai/install.ps1` are not hash-checked.
- [ ] `C:\DevDrives` inherits `C:\` permissions, but the boot task mounts the VHDX as
  SYSTEM. Tighten its ACL.
- [ ] The expandable VHDX never shrinks after files are deleted.
- [ ] `winget upgrade --all` can upgrade the app running the script (WezTerm, pwsh),
  or a running Rancher Desktop.
- [ ] Dead code: `Ensure-FontPackageRegistered` (`setup-windows.ps1:367`).
- [ ] `Get-SetupConfig` executes the `$Config` right-hand side; use
  `HashtableAst.SafeGetValue()`.
- [ ] Over-engineered for the value: the font detection machinery (`:292-492`), and
  the regex spot-checks of the WezTerm file in the audit (a `-RenderConfig` diff, like
  Ubuntu's `--render-rc`, would be simpler and complete).
- [ ] BitLocker: on an Intune-managed PC the VHDX-backed `D:` is an unencrypted fixed
  data volume, and may fail a policy that requires encrypting fixed drives
  (unverified; check with IT).

## 3. Tool selection

**Keep:** git, gh, delta, lazygit, ripgrep, fd, fzf, bat, jq, yq, zoxide, starship,
direnv, kubectl, helm, k9s, kubectx, kubelogin, stern, sops, OpenTofu, azd, uv, Claude
Code, WezTerm, pwsh 7, VS Code, PowerToys, `dotnet-install.sh`.

**Add:**
- [ ] **Azure CLI (`az`) on Ubuntu.** It's only installed on Windows today, but on WSL
  you need it for `az aks get-credentials`, for kubelogin's `azurecli` mode, and for
  Bicep. docs/ubuntu.md already tells users to run `az aks get-credentials`.
- [ ] **`age`**, if sops is meant for age keys and not only Key Vault.

**Replace:**
- [ ] **fnm and the ~12 GitHub-release installers → mise** (A1). Also consider letting
  mise's per-folder environment variables replace direnv for KUBECONFIG; keeping direnv
  is fine.
- [ ] **pipx → uv.** `uv tool install` does the same job, and uv is already installed,
  currently through pipx.
- [ ] **Rancher Desktop Kubernetes: off by default.** k3s holds memory all day. Turn it
  on when needed, or use kind or k3d per project.

**Rethink:**
- [ ] **oh-my-zsh** ([ADR 0007](../adr/0007-starship-prompt-omz-framework-only.md)). It
  is used for git aliases, completion setup and tab titles, while Starship, fzf-tab,
  autosuggestions and syntax highlighting are loaded separately. Much of the plugin and
  load-order complexity exists to work around it. A lighter plugin loader (antidote),
  or sourcing the plugins directly plus a small aliases file, would start faster and
  need less special handling. Measure startup time first (`zsh -i -c exit` with
  `zprof`).
- [ ] **Codex** is installed with winget on Windows and npm on Ubuntu. Use one channel,
  or drop it if it isn't used.
- [ ] **7-Zip.** Windows 11 now extracts 7z and rar itself. Optional.
- [ ] **dotnet-outdated.** .NET 10's built-in `dotnet package list --outdated` covers
  the read-only use. Low priority.
- [ ] **Marginal tools** (glow, eza, the WezTerm dev layout, the Windows font detection):
  fine to keep, but each adds an update path and audit code. With mise most of that
  cost goes away; without it, trim.

## 4. Suggested order

1. **Quick fixes:** B1 `.gitattributes`, B2 reboot-pass exit, B3 font audit, B4
   `run_step`, B5 kubectl `/mnt/c`, and `az` on Ubuntu.
2. **Scheduled CI** that runs the update script and checks the pins (A4).
3. **mise trial on a branch**, measuring the lines removed (A1, A2). Write an ADR on
   the outcome.
4. **Windows split** into an elevated WinGet Configuration and a per-user script (A3,
   W5). Write an ADR.
5. Everything else as it comes up.

## Notes

- The Windows findings come from a subagent review of `bootstrap-windows.ps1`,
  `setup-windows.ps1`, `update-windows.ps1` and `audit-windows.ps1`. B1, B2 and B3 were
  spot-checked against the code. Items marked *unverified* were inferred, not tested.
- Line numbers refer to commit `93b0236`.

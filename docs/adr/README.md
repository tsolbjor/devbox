# Architecture decision records

Why devbox is built the way it is. Each record captures one decision: the context,
what was decided, and what it costs. See [0001](0001-record-architecture-decisions.md)
for how they work.

## Adding one

1. Copy [template.md](template.md) to `NNNN-short-title.md`, using the next free number.
2. Fill it in. Status starts as **Proposed**, and becomes **Accepted** once it is merged.
3. Add a row to the table below.
4. To reverse a decision, write a new ADR and mark the old one
   `Superseded by [NNNN](…)`. Don't rewrite history.

Work that is planned but not yet decided or built belongs in [../plans/](../plans/).

## Index

| # | Decision | Status | Date |
|---|---|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions in docs/adr | Accepted | 2026-11-08 |
| [0002](0002-idempotent-scripts-with-parsed-audit.md) | Idempotent ensure-scripts, with audits that parse setup for the expected state | Accepted | 2026-07-12 |
| [0003](0003-generated-shell-config.md) | Generate the WSL shell config into ~/.config/devbox | Accepted | 2026-09-26 |
| [0004](0004-node-via-fnm-shared-npm-prefix.md) | Node via fnm, npm globals in one shared prefix | Accepted | 2026-09-26 |
| [0005](0005-dotnet-via-dotnet-install.md) | .NET SDK from dotnet-install.sh into ~/.dotnet, not apt | Accepted | 2026-11-02 |
| [0006](0006-claude-code-native-installer.md) | Claude Code from the native installer, not winget or npm | Accepted | 2026-09-24 |
| [0007](0007-starship-prompt-omz-framework-only.md) | Starship is the only prompt; oh-my-zsh as a framework only | Accepted | 2026-08-05 |
| [0008](0008-windows-gcm-for-wsl-https.md) | HTTPS Git auth in WSL through the Windows Git Credential Manager | Accepted | 2026-09-26 |
| [0009](0009-detect-wsl-vs-native.md) | Detect WSL from WSL_DISTRO_NAME or /run/WSL, never /proc/version | Accepted | 2026-10-21 |
| [0010](0010-dev-drive-vhdx.md) | A VHDX-backed Dev Drive at D:, created by the bootstrap | Accepted | 2026-07-12 |
| [0011](0011-reconcile-version-pins-explicitly.md) | Version pins are reconciled explicitly; reruns never move them | Accepted | 2026-09-24 |
| [0012](0012-powershell-utf8-bom.md) | PowerShell scripts are UTF-8 with a BOM; the bootstrap is pure ASCII | Accepted | 2026-09-26 |
| [0013](0013-rancher-desktop-container-engine.md) | Rancher Desktop (moby) is the container engine | Accepted (rationale reconstructed) | 2026-02-28 |

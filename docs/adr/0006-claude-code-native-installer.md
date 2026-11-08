# 0006. Claude Code from Anthropic's native installer, not winget or npm

- **Date:** 2026-09-24
- **Status:** Accepted

## Context

The native Claude Code build updates itself in the background. The winget package
cannot replace a running `claude.exe`, and the npm global ties `claude` to whichever
Node fnm has active. Two installs on one PATH mean the winner is whichever directory
comes first.

## Decision

`ensure_claude_code` / `Ensure-ClaudeCode` use Anthropic's installer
(`claude.ai/install.sh` / `install.ps1`). On Windows it is the only app installed
outside winget. Both functions remove an earlier winget or npm copy. There is no
`update-*` step for it.

## Consequences

`audit-windows.ps1` checks it separately from the winget inventory and flags a
non-native `claude.exe` that wins the PATH race.

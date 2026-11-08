# 0011. Version pins are reconciled explicitly; reruns never silently move them

- **Date:** 2026-09-24
- **Status:** Accepted

## Context

`DOTNET_SDK_VERSION`, `KUBECTL_VERSION` and `NODE_MAJOR_VERSION` track upstream
support windows. Moving them on an existing machine changes what every shell (or
every cluster call) gets, so it should not happen as a side effect of a routine
rerun. At the same time, an `ensure_*` that short-circuits on "command present"
hides a stale pin forever.

## Decision

- **dotnet:** SDKs install side by side, so `ensure_dotnet` keys on the pinned SDK.
  A rerun adds it and removes nothing.
- **node:** a rerun installs the pinned major under fnm but leaves the default where
  it is and warns. `update-ubuntu.sh --pins` moves the default, after asking.
- **kubectl:** installing replaces the minor, so `ensure_kubectl` stays guarded on
  "present". `--pins` rewrites the apt source, after asking.
- `audit-ubuntu.sh` compares all three against the pins parsed out of setup.
- Everything else floats: apt, winget and GitHub-release tools resolve `latest`.

## Consequences

Pins go stale silently unless someone checks. CLAUDE.md keeps a "Reviewed" table,
and the [2026-11-08 review plan](../plans/2026-11-08-stack-review.md) proposes a
scheduled CI check.

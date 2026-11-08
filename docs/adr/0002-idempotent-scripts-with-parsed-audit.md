# 0002. Idempotent ensure-scripts, with audits that parse setup for the expected state

- **Date:** 2026-07-12
- **Status:** Accepted

## Context

A developer machine is set up once and then lives for years. Scripts that only work
on a blank machine are useless after day one, and a separate list of what *should*
be installed drifts away from what setup actually installs.

## Decision

- Every step is an `ensure_*` / `Ensure-*` function: check the current state, skip
  if it is already right, act and report if it is not (`✓` / `→` / `⚠`). Every
  script is safe to rerun.
- `audit-ubuntu.sh` / `audit-windows.ps1` are read-only. They derive the expected
  state by **parsing the setup scripts**: the `APT_PACKAGES` array and `ensure_*`
  calls, and the `$Config` hashtable (AST) with the literal `-Id` /
  `npm install -g` calls. There is no second list.
- CI runs `setup-ubuntu.sh` twice in a blank container. The second run must print no
  `→` line, and the audit must then find no drift.

## Consequences

- Setup scripts must keep certain things literal (`npm install -g <pkg>`,
  `ensure_dotnet_tool <pkg> <cmd>`) so the audit can find them. Renaming `$Config`
  keys or the package array breaks the audit.
- Every new tool needs an `ensure_*`, an `update_*` and audit coverage. See the
  [2026-11-08 review plan](../plans/2026-11-08-stack-review.md) for a proposal to
  reduce that.

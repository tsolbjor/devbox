# 0004. Node via fnm, with npm globals in one shared prefix

- **Date:** 2026-09-26
- **Status:** Accepted

## Context

Client repos pin their own Node version (`.nvmrc`, `.node-version`). apt's `nodejs`
and NodeSource give one system-wide version. nvm switches versions but slows shell
startup. fnm gives each Node version its own npm prefix, so global CLIs vanish on
every patch bump.

## Decision

- Node comes from fnm on both Windows (`Ensure-Node`) and WSL (`ensure_node`).
  fnm switches on `cd` through the managed rc block. `NODE_MAJOR_VERSION` /
  `NodeMajorVersion` set only the fnm *default*.
- npm globals go to one prefix shared by every Node version: `NPM_GLOBAL_PREFIX`
  (`~/.local`) on WSL, `%APPDATA%\npm` on Windows.
- Older installs (apt `nodejs`, NodeSource, nvm, nvm-windows, root-owned globals)
  are migrated only after asking: `MIGRATE_LEGACY_NODE=ask|yes|no`.

## Consequences

Global CLIs survive Node upgrades and per-project switches. A rerun installs the
pinned major but never moves the default; see [0011](0011-reconcile-version-pins-explicitly.md).

# 0010. A VHDX-backed Dev Drive at D:, created by the bootstrap

- **Date:** 2026-07-12
- **Status:** Accepted

## Context

A blank, Entra-joined PC has no Git and usually no free partition for a `D:` drive.
Microsoft recommends a ReFS Dev Drive for source code and package caches: it is
faster, and it is trusted, so Defender skips real-time scanning of it.

## Decision

`bootstrap-windows.ps1` (run as `irm | iex`) verifies winget, installs Git, creates
an expandable VHDX formatted as a ReFS Dev Drive at `D:` (falling back to NTFS on
older builds), registers a boot-time task (`DevboxMountDevDrive`) that re-attaches it,
and clones this repo to `D:\code\devbox`. It installs no apps. `setup-windows.ps1`
then moves the npm and NuGet caches to `D:\packages`.

## Consequences

- `bootstrap-windows.ps1` must stay pure ASCII ([0012](0012-powershell-utf8-bom.md)).
- The VHDX never shrinks. Its BitLocker status on managed PCs, and recovery from a
  half-finished first run, are open items in the
  [2026-11-08 review plan](../plans/2026-11-08-stack-review.md).

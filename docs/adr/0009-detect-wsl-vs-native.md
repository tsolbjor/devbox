# 0009. Detect WSL from WSL_DISTRO_NAME or /run/WSL, never /proc/version

- **Date:** 2026-10-21
- **Status:** Accepted

## Context

The Ubuntu scripts also run on native Ubuntu and in containers (CI). The Windows-facing
steps (`/etc/wsl.conf`, GCM, Git identity from Windows, the Rancher Desktop docker
check) must not run there. `/proc/version` says "microsoft" inside a container on a
WSL host too, so it misdetects containers as WSL.

## Decision

`detect_devbox_env` resolves `DEVBOX_ENV=auto` to `wsl` when `WSL_DISTRO_NAME` is set
(sudo drops it) or `/run/WSL` exists. Otherwise it is `native`. Settings that default
to `auto` (`CONFIGURE_WSL_CONF`, `USE_WINDOWS_GCM`) follow it through `resolve_auto`.
New WSL-only steps are guarded with `on_wsl`. `--detect-env` exposes the result to the
audit, so there is only one copy of the detection logic.

## Consequences

CI runs the setup once per `DEVBOX_ENV` (`native`, and `wsl` forced) to cover both
paths.

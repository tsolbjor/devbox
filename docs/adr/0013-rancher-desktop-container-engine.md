# 0013. Rancher Desktop (moby) is the container engine on Windows and WSL

- **Date:** 2026-02-28
- **Status:** Accepted

> Recorded retroactively. The original rationale was not written down. The context
> below is reconstructed and should be confirmed or corrected.

## Context

Containers and a local Kubernetes are needed on the Windows host and inside WSL.
Docker Desktop requires a paid subscription for larger companies. Installing a
second `dockerd` inside WSL competes with the host engine for the socket.

## Decision

`setup-windows.ps1` installs Rancher Desktop and merges its `settings.json`, never
replacing it, with the moby engine (Docker-compatible CLI) and Kubernetes enabled.
`setup-ubuntu.sh` installs no engine. On WSL, `docker_check` expects Rancher's WSL
integration, and `audit-ubuntu.sh` flags shadow apt or snap `dockerd` installs.

## Consequences

WSL's docker and kubectl come from Rancher's Windows-side binaries under `/mnt/c`.
That shadows the apt kubectl (a known bug, see the review plan). Whether Kubernetes
should be on by default is an open question in the
[2026-11-08 review plan](../plans/2026-11-08-stack-review.md).

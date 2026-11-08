# 0008. HTTPS Git auth in WSL goes through the Windows Git Credential Manager

- **Date:** 2026-09-26
- **Status:** Accepted

## Context

Azure DevOps clients mostly hand out HTTPS remotes and authenticate with Entra.
Signing in separately on both sides of the WSL boundary, or storing PATs in plain
text, is worse than one shared login.

## Decision

On WSL (`USE_WINDOWS_GCM=auto`), `ensure_git_credential_manager` sets
`credential.helper` to Git for Windows' `git-credential-manager.exe`
(`find_windows_gcm` looks in ucrt64, mingw64 and clangarm64).
`credential.https://dev.azure.com.useHttpPath=true` is scoped to Azure DevOps, not
set globally: a global setting makes GCM store a separate GitHub credential for
every repository.

## Consequences

WSL depends on Git for Windows being installed (setup-windows.ps1 does that). On
native Ubuntu nothing is set, and `gh auth login` covers GitHub.

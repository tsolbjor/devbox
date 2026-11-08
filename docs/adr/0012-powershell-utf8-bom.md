# 0012. PowerShell scripts are UTF-8 with a BOM; the bootstrap is pure ASCII

- **Date:** 2026-09-26
- **Status:** Accepted

## Context

Windows PowerShell 5.1, which a fresh machine runs, reads a BOM-less file as
Windows-1252. The UTF-8 bytes of `✓`, `→` and `—` include 0x93/0x94, which it parses
as curly-quote string delimiters, so the scripts failed to load. pwsh 7 hides the
problem. `bootstrap-windows.ps1` also runs as `irm | iex`, where a BOM becomes a
stray U+FEFF that breaks the first command.

## Decision

Every `.ps1` run from disk is saved as UTF-8 with a BOM. `bootstrap-windows.ps1`
stays pure ASCII and builds its status glyphs from code points.
`.github/ci/Test-WindowsPowerShellLoad.ps1` checks, under Windows PowerShell 5.1,
that every script loads.

## Consequences

New `.ps1` files need a BOM added by hand; the editing tools preserve an existing one.
Files the scripts *write* (`.wslconfig`, Rancher's `settings.json`) are a separate
concern: `Set-Content -Encoding UTF8` on 5.1 adds a BOM to them too, which is an open
item in the review plan.

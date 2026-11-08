# 0005. .NET SDK from dotnet-install.sh into ~/.dotnet, not apt

- **Date:** 2026-11-02
- **Status:** Accepted

## Context

Ubuntu's `dotnet-sdk-*` packages are source-built and only ever ship the 1xx feature
band, so `apt upgrade` never reaches 10.0.4xx. A repo whose `global.json` asks for
10.0.403 cannot build, because SDK roll-forward only moves up.

## Decision

`ensure_dotnet` runs Microsoft's `dotnet-install.sh --channel $DOTNET_SDK_VERSION`
into `DOTNET_INSTALL_DIR` (`~/.dotnet`). The pin is a channel (`10.0`), not a band.
The generated rc sets `DOTNET_ROOT` and puts the directory ahead of `/usr/bin/dotnet`.
`ensure_dotnet_deps` installs ICU from apt. `migrate_apt_dotnet` reinstalls every SDK
major an older apt install held, then purges the apt packages, after asking
(`MIGRATE_APT_DOTNET`). Global tools are shimmed from `~/.dotnet/tools` into
`~/.local/bin`.

## Consequences

`update-ubuntu.sh` (`update_dotnet`) moves each installed major to its newest band
and patch. SDKs install side by side, so bumping the pin and rerunning setup adds the
new SDK and removes nothing.

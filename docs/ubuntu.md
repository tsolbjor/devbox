# Ubuntu / WSL setup

Covers `setup-ubuntu.sh`, which runs inside WSL2 or on a standalone (native)
Ubuntu machine. For the short version, see the [Quick Start](../README.md#quick-start).

## Prerequisites

- Ubuntu 20.04 LTS or later — inside WSL2, or native
- sudo access

## Running it

Inside your Ubuntu terminal:

```bash
bash setup-ubuntu.sh
```

The script detects where it runs (`DEVBOX_ENV=auto`) and prints it first:

| | WSL | Native Ubuntu |
|---|---|---|
| `/etc/wsl.conf` | merged | skipped |
| Git identity | existing Git config, else the Windows (Entra) user | existing Git config, else `GIT_NAME`/`GIT_EMAIL` required |
| HTTPS Git auth | Git for Windows' Credential Manager | none set — `gh auth login` covers GitHub |
| Docker | checks Rancher Desktop's WSL integration | checks any engine answers; installs none |

Force either path with `DEVBOX_ENV=wsl` / `DEVBOX_ENV=native` (a container always detects as native).

Unless the global Git config already has them, Git name/email auto-detect on WSL from
the logged-in Windows (Entra) user — email from the UPN (`whoami.exe /upn`), name
from the Windows logon display name. Override by exporting them first (required
on a fresh native machine), or set `AUTO_DETECT_GIT_IDENTITY=false` to disable:

```bash
export GIT_NAME="Your Name"
export GIT_EMAIL="your@email.com"
bash setup-ubuntu.sh
```

After the script finishes it prints your SSH public key and next steps.

## What gets installed and configured

| Category | What gets set up |
|---|---|
| Shell | zsh (set as default), Starship, fzf, zoxide, zsh-autosuggestions + zsh-syntax-highlighting — all configured in a generated `~/.config/devbox/<shell>rc`; your `~/.zshrc`/`~/.bashrc` only gets one loader block, and stays yours |
| Shell UX | 200 000-line history for bash and zsh (flushed per command), inline suggestions in a readable colour, PSReadLine-style accept keys (`→`, `Ctrl+→`, `Tab`), `Ctrl+R` history picker |
| Dev tools | git, build-essential, ripgrep, fd, bat, eza, jq, yq, sops, wget, zip, git-delta, lazygit, glow, yazi, micro, GitHub CLI, Node.js via fnm |
| Agentic CLIs | Claude Code (native install, self-updating), Codex (npm global) |
| Languages | .NET SDK (10 LTS, newest feature band, in `~/.dotnet` — Ubuntu's apt feed stops at 1xx), Aspire CLI, `dotnet outdated` (NuGet's `ncu`), Python (venv/pip/pipx/uv) |
| Azure | Azure Developer CLI (`azd`) — provisions and deploys an Aspire AppHost |
| Kubernetes | kubectl, helm, k9s, kubectx, kubens, stern, kubelogin (Entra auth for AKS); a kubeconfig per folder via direnv (below) |
| Containers | verifies docker answers — on WSL, that Rancher Desktop's docker is wired in |
| Git | user config (on WSL auto-detected from Windows), defaults, SSH commit signing, on WSL HTTPS auth via the Windows Git Credential Manager |
| SSH | ed25519 key pair |
| System | on WSL: /etc/wsl.conf (automount metadata, systemd — merged key by key, other settings kept) |

Keyboard shortcuts and how-tos for the shell tools are in the
[terminal cheatsheet](cheatsheet.md).

## A kubeconfig per folder

direnv (hooked into the generated shell config) exports `KUBECONFIG` from an
`.envrc` when you `cd` into its tree and drops it when you leave, so kubectl, k9s,
helm, stern and kubectx all see the cluster of the folder you are in. Put the
`.envrc` in the folder *above* a client's repos — one file covers all of them, and
no credentials path lands in a repo:

```bash
mkdir -p ~/.kube/clients && chmod 700 ~/.kube ~/.kube/clients
echo 'export KUBECONFIG="$HOME/.kube/clients/acme.yaml"' > ~/code/acme/.envrc
direnv allow ~/code/acme     # once, and again whenever the .envrc changes

cd ~/code/acme/some-repo
az aks get-credentials -g <rg> -n <cluster> --file "$KUBECONFIG"   # az ignores KUBECONFIG without --file
kubelogin convert-kubeconfig -l azurecli                           # Entra clusters
k9s
```

Each folder's `kubectx` / `kubens` switches only rewrite that folder's file, so two
terminals in two clients never move each other's current context. Outside any
`.envrc` tree, `~/.kube/config` applies as usual. To see the context in the prompt,
set `[kubernetes] disabled = false` in `~/.config/starship.toml`.

## Customisation

The script has a `PARAMETERS` section at the very top — edit values there (or
export them as env vars) before running. No changes to the implementation section
are needed for common adjustments.

Set `INSTALL_KUBECTL=false` to skip Kubernetes tools; toggle `INSTALL_DOTNET` /
`INSTALL_PYTHON` (or pin `DOTNET_SDK_VERSION`; a machine with apt's `dotnet-sdk-*`
from an older setup is offered a move to `~/.dotnet` — `MIGRATE_APT_DOTNET=yes|no`
answers for it); set `GIT_SIGN_COMMITS=false` to skip SSH commit signing; change
`STARSHIP_PRESET` to any name from [starship.rs/presets](https://starship.rs/presets/)
(or empty for the built-in default); set `WSL_ENABLE_SYSTEMD=false` on older
Windows builds.

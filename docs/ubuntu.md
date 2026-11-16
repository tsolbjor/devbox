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
| Kubernetes | kubectl, helm, k9s, kubectx, kubens, stern, kubelogin (Entra auth for AKS); a kubeconfig per folder via mise (below) |
| Per-folder env | mise (`mise.toml` `[env]`, the devbox convention, same as pwsh); direnv for repos that ship their own `.envrc` |
| Azure | Azure CLI (Microsoft's apt repo, extensions in one shared `AZURE_EXTENSION_DIR`), `azd` signing in through az; an az login per folder via mise (below) |
| Containers | verifies docker answers — on WSL, that Rancher Desktop's docker is wired in |
| Git | user config (on WSL auto-detected from Windows), defaults, SSH commit signing, on WSL HTTPS auth via the Windows Git Credential Manager |
| SSH | ed25519 key pair |
| System | on WSL: /etc/wsl.conf (automount metadata, systemd — merged key by key, other settings kept) |

Keyboard shortcuts and how-tos for the shell tools are in the
[terminal cheatsheet](cheatsheet.md).

## A kubeconfig and az login per folder

mise (hooked into the generated shell config) applies the `[env]` of a trusted
`mise.toml` when you `cd` into its tree and drops it when you leave. Two variables
pick a client's cluster and Azure tenant:

- `KUBECONFIG` — kubectl, k9s, helm, stern and kubectx all use the folder's cluster
- `AZURE_CONFIG_DIR` — az uses the folder's own login, tenant and default
  subscription. So do kubelogin's `azurecli` mode, `AzureCliCredential` in apps you
  start from that shell, and azd, which setup points at az's login.

Put the `mise.toml` in the folder *above* a client's repos. One file covers all of
them, and no credentials path lands in a repo:

```bash
mkdir -p ~/.kube/clients && chmod 700 ~/.kube ~/.kube/clients
cat > ~/code/acme/mise.toml <<'EOF'
[env]
KUBECONFIG       = "{{env.HOME}}/.kube/clients/acme.yaml"
AZURE_CONFIG_DIR = "{{env.HOME}}/.azure-clients/acme"
EOF
mise trust ~/code/acme       # once, and again whenever the file changes

cd ~/code/acme/some-repo
az login --tenant <tenant>                                         # lands in the folder's AZURE_CONFIG_DIR
az aks get-credentials -g <rg> -n <cluster> --file "$KUBECONFIG"   # az ignores KUBECONFIG without --file
kubelogin convert-kubeconfig -l azurecli                           # Entra clusters
k9s
```

Write `{{env.HOME}}`, not `~`: mise does not expand `~` in `[env]` values. az
extensions stay shared, because setup sets `AZURE_EXTENSION_DIR` to one directory.
`mise env` shows what applies in the current folder.

Each folder's `kubectx` / `kubens` switches only rewrite that folder's file, so two
terminals in two clients never move each other's current context. Outside any
`mise.toml` tree, `~/.kube/config` and `~/.azure` apply as usual. To see the
context in the prompt, set `[kubernetes] disabled = false` in
`~/.config/starship.toml`. The pwsh side works the same way
([windows.md](windows.md#a-kubeconfig-and-az-login-per-folder)).

direnv stays installed and hooked for repos that ship their own `.envrc` (`direnv
allow` it as before). For a folder of your own, prefer `mise.toml`: it works the
same in pwsh. A plain `.envrc` of yours with only `export` lines moves over as-is,
each line becoming an `[env]` key.

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

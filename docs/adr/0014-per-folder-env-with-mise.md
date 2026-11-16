# 0014. Per-folder environment with mise on both platforms; direnv kept for repos' own .envrc

- **Date:** 2026-11-11
- **Status:** Accepted

## Context

Client work means one cluster and one Azure tenant per client. Two variables
select both: `KUBECONFIG` (kubectl, k9s, helm, stern, kubectx) and
`AZURE_CONFIG_DIR` (az, which also covers kubelogin's `azurecli` mode and
`AzureCliCredential` in apps started from the shell). Setting them per folder
means a terminal in `~/code/acme` cannot act on another client's cluster or
subscription, and two terminals in two clients do not move each other's context.

On WSL, commit 93b0236 did this with direnv hooked into the generated rc. The pwsh
side had nothing. direnv on Windows runs `.envrc` through Git Bash, which adds a
bash dependency and a POSIX/Windows path translation question for every path
handed to `kubectl.exe`. A hand-written pwsh prompt hook would be a second
mechanism that only covers the variables it was written for.

## Decision

mise is installed on both platforms and used for its `[env]` only. A
`mise.toml` above a client's repos sets the variables, and `mise trust` approves
it, just as `direnv allow` did:

- **Ubuntu:** `ensure_mise` installs from mise's apt repo. The generated rc
  activates it after starship (`render_devbox_prompt_tools`), so starship's precmd
  hook records `$?` first. direnv stays in `APT_PACKAGES` and stays hooked, for
  repos that commit their own `.envrc`. Those often use direnv's stdlib
  (`watch_file`, `source_env_if_exists`, `log_error`), which no `[env]` table can
  express, and the repo, not devbox, decides that.
- **Windows:** `Ensure-Mise` installs `jdx.mise` from winget and writes a `mise`
  managed profile block. That block has to come after the Starship line, because
  mise wraps the `prompt` function. Setup warns and the audit reports drift when
  the order is wrong.

What makes a per-folder `AZURE_CONFIG_DIR` practical on both platforms:

- `AZURE_EXTENSION_DIR` points at az's default extension dir: a line in the
  generated rc on Ubuntu, a user env var from `Ensure-AzureCliSettings` on
  Windows. Without it az keeps extensions inside each config dir.
- azd is set to `auth.useAzCliAuth true` (`AZD_USE_AZ_CLI_AUTH`,
  `$Config.AzureCli.AzdUseAzCliAuth`), so it uses az's login for the folder
  instead of a login of its own.
- az is now installed on Ubuntu as well (`ensure_azure_cli`, Microsoft's apt repo).

Windows also gains k9s, kubectx, kubens and stern in `CloudCLIs`, so the
Kubernetes tools a folder's `KUBECONFIG` serves are the same on both sides.

## Alternatives considered

- **Replace direnv with mise outright:** this breaks every repo that ships its own
  `.envrc`, and a team's repo cannot be asked to change for one person's shell.
- **Keep direnv as the convention on Ubuntu, add direnv on Windows:** `.envrc`
  would run through Git Bash, with path translation for Windows binaries and two
  shells to support.
- **Keep direnv on Ubuntu, write a small pwsh hook on Windows:** two mechanisms
  and two file formats to document and audit.
- **Replace fnm and the GitHub-release installers with mise at the same time**
  (stack review A1): a much larger change. It stays a separate decision, and
  nothing here blocks it.

## Consequences

- One file format and one command (`mise trust`) on both platforms. The files
  themselves are not shared, because Windows and WSL keep separate homes and code
  trees.
- Two per-folder mechanisms are hooked on Ubuntu: mise for devbox's own
  convention, direnv for repos' `.envrc`. If a folder has both, both apply.
  Avoid setting the same variable in both, because which one wins comes down to
  hook timing.
- A `mise.toml` can also hold `[tools]`. mise then puts those tools on PATH, and
  can install them on first use. mise reads no idiomatic version files by default,
  so `.nvmrc` stays fnm's.
- Windows PowerShell 5.1 has no cd hook, so there `[env]` applies at the next
  prompt rather than mid-line. pwsh 7 applies it on `cd`.
- GUI tools (VS Code's Azure extensions, Visual Studio) do not read the shell's
  environment. The separation covers the CLI only.

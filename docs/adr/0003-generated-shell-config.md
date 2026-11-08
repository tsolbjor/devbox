# 0003. Generate the WSL shell config into ~/.config/devbox, with one loader block in the rc files

- **Date:** 2026-09-26
- **Status:** Accepted

## Context

`setup-ubuntu.sh` used to write about a dozen separate things into `~/.zshrc` and
`~/.bashrc`: appended init lines, `sed` edits and managed blocks at anchors. The zsh
pieces only worked in one order, and the audit had to compare line numbers to check
it. On a fresh machine that order was already wrong.

## Decision

`ensure_devbox_shell_config` writes `~/.config/devbox/{zshrc,bashrc}` whole on every
run (`render_devbox_rc`). The rc files carry only a `devbox: loader` block that
sources it. The render is a **pure function of PARAMETERS**: it probes nothing.
Every section is guarded at shell start, so a missing tool is skipped and the shell
still starts. `setup-ubuntu.sh --render-rc zsh|bash` reproduces the file, and the
audit diffs against it.

Migration (`migrate_rc_to_devbox_config`) removes only exact lines and marked blocks
that older setups wrote, and keeps a one-time `.pre-devbox-config.bak`. It is pinned
by `.github/ci/rc-migration-test.sh` and its fixtures.

## Alternatives considered

- Keep managed blocks in the user's rc file. Load order then depends on where the
  user's own lines sit, and auditing it means checking positions.

## Consequences

The load order is fixed in a file setup owns. To change what a shell gets, edit the
`render_devbox_*` functions; never append to `~/.zshrc`. Lines the user puts after
the loader still win, which is why the audit reads the effective values from a real
`zsh -ic`.

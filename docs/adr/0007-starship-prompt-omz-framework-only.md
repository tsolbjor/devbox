# 0007. Starship is the only prompt; oh-my-zsh is loaded as a framework only

- **Date:** 2026-08-05
- **Status:** Accepted

## Context

The prompt was rendered by oh-my-posh on Windows and an oh-my-zsh theme in WSL.
Two prompt engines in one shell fight over the prompt hooks. The apt build of
zsh-autosuggestions (0.7.0) stops drawing inline suggestions in this stack.

## Decision

- Starship renders the prompt in pwsh (PS5 and PS7) and in zsh/bash.
- oh-my-zsh is installed for completion defaults, git aliases and tab titles only,
  with `ZSH_THEME=""`.
- zsh-autosuggestions, zsh-syntax-highlighting and fzf-tab load from oh-my-zsh
  `custom/plugins` git clones. The apt packages are only a fallback, and each plugin
  loads exactly once.

## Consequences

One prompt configuration (`starship.toml`) covers both platforms. Whether oh-my-zsh
is still worth its startup cost is an open question in the
[2026-11-08 review plan](../plans/2026-11-08-stack-review.md).

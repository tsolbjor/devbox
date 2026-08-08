# Terminal cheatsheet

Quick reference for the terminal this devbox sets up: **WezTerm** + **Starship** and the
CLI addons. Keys marked **(custom)** are configured by these scripts; the rest are the
tool's own defaults.

> Where things live: WezTerm → `~/.wezterm.lua` · Starship → `~/.config/starship.toml`
> (one on Windows, one inside WSL). See [Configs & how to change defaults](#configs--how-to-change-defaults).

---

## WezTerm

### Quick shell switching **(custom)**

The `+` button dropdown in the tab bar lists these, and the keys spawn them directly:

| Key | Opens |
|---|---|
| `Ctrl+Shift+1` | **cmd** |
| `Ctrl+Shift+2` | **pwsh** (starts in `D:\code`) |
| `Ctrl+Shift+3` | **Ubuntu** (WSL) |
| `Ctrl+Shift+L` | **Launcher menu** (pick any of the above) |

New tabs/windows open **Ubuntu** by default (that's the default domain).

### Tabs & windows

| Key | Action |
|---|---|
| `Ctrl+Shift+T` | New tab |
| `Ctrl+Shift+W` | Close tab |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Next / previous tab |
| `Ctrl+Shift+N` | New window |
| `Alt+Enter` | Toggle full screen |

### Copy / paste / scroll / search

| Key | Action |
|---|---|
| `Ctrl+Shift+C` / `Ctrl+Shift+V` | Copy / paste |
| Mouse drag | Select (auto-copies on release) |
| `Shift+PageUp` / `Shift+PageDown` | Scroll history (30 000 lines kept) |
| `Ctrl+Shift+F` | Search scrollback |
| `Ctrl+Shift+X` | Copy mode (select text with the keyboard; `v` start, `y` yank, `Esc` exit) |
| `Ctrl+Shift+Space` | Quick-select (jump to URLs/paths/hashes on screen) |
| `Ctrl+Shift+P` | **Command palette** — search every action by name |

> Forgot a key? `Ctrl+Shift+P` and start typing — the command palette shows the binding.

### Font & appearance

| Key | Action |
|---|---|
| `Ctrl+=` / `Ctrl+-` | Zoom font in / out |
| `Ctrl+0` | Reset font size |

Configured look: JetBrainsMono Nerd Font 12pt, `OneHalfDark` scheme, steady-bar cursor,
bell off. The tab bar hides itself when only one tab is open.

### Panes **(custom)**

Tmux-style split panes:

| Key | Action |
|---|---|
| `Ctrl+Shift+D` | Split **right** (side by side) |
| `Ctrl+Shift+E` | Split **down** (stacked) |
| `Ctrl+Shift+←/→/↑/↓` | Move focus between panes |
| `Ctrl+Shift+Z` | Zoom the active pane (toggle full-tab) |

A split inherits the current pane's shell (e.g. splitting an Ubuntu pane gives another
Ubuntu pane). Close a pane by exiting its shell (`exit` / `Ctrl+D`).

### Reloading config

WezTerm **auto-reloads** `~/.wezterm.lua` on save — no restart needed. If a change is
ignored, you likely have a Lua syntax error; run `wezterm` from a shell to see the error,
or check the debug overlay.

---

## Starship prompt

The prompt is built from left to right: **directory**  **git branch**  **git status** 
**language/tool versions** (Node, Python, .NET, etc., shown only in relevant dirs) 
**duration** (for slow commands)  a `❯` that turns red on the last command's failure.

### Git status symbols

Shown after the branch, e.g. ` main [!?⇡2]`:

| Symbol | Meaning |
|---|---|
| `!` | Modified (unstaged) |
| `+` | Staged |
| `?` | Untracked |
| `»` | Renamed |
| `✘` | Deleted |
| `$` | Stashed |
| `⇡N` / `⇣N` | Ahead / behind remote by N |
| `⇕` | Diverged |
| `=` | Conflicts |

### Customizing

| Command | Does |
|---|---|
| `starship explain` | Explains every module in your current prompt |
| `starship preset --list` | List available presets |
| `starship preset nerd-font-symbols -o ~/.config/starship.toml` | Re-apply the configured preset |
| `starship config` | Open `starship.toml` in `$EDITOR` |
| `starship timings` | Find which module is making the prompt slow |

Edit `~/.config/starship.toml` to tweak. Common tweaks:

```toml
# Hide a module
[package]
disabled = true

# Add a newline before each prompt
add_newline = true

# Shorten long paths
[directory]
truncation_length = 3
```

> Setup applies the `nerd-font-symbols` preset **only if no `starship.toml` exists** — it
> never overwrites your edits. Windows and WSL each have their own file.

---

## Terminal addons

### zoxide — smarter `cd`

Learns the directories you visit; jump by a fragment of the name.

| Command | Does |
|---|---|
| `z proj` | Jump to the best-matching dir containing "proj" |
| `z foo bar` | Match on multiple fragments |
| `z -` | Back to previous directory |
| `zi proj` | Interactive pick (fzf) among matches |

### fzf — fuzzy finder

Wired into bash/zsh **and** PowerShell (via PSFzf):

| Key | Does |
|---|---|
| `Ctrl+T` | Insert file/dir path(s) into the command line |
| `Ctrl+R` | Fuzzy-search command history |
| `Alt+C` | `cd` into a subdirectory *(bash/zsh only)* |
| `**<Tab>` | Fuzzy-complete after a command *(bash/zsh)*, e.g. `vim **<Tab>` |

In the picker: type to filter, `Tab` to multi-select, `Enter` to accept, `Esc` to cancel.

### bat — `cat` with highlighting

`bat file.ts` (syntax-highlighted, paged) · `bat -A file` (show whitespace/tabs) ·
`bat -l json` (force a language). It's the pager behind git-delta too.

### eza — modern `ls`

Setup wires these aliases into `.bashrc`/`.zshrc` for you:

| Alias | Expands to |
|---|---|
| `ls` | `eza --icons` |
| `ll` | `eza -la --icons --git` (long, hidden, git status column) |
| `lt` | `eza --tree --level=2 --icons` |

Direct flags still work too: `eza -l --git`, `eza --tree`, `eza -la`.

### git-delta — better diffs

Automatic for `git diff`, `git show`, `git log -p`, `git blame`. Inside the pager:

| Key | Does |
|---|---|
| `n` / `N` | Jump to next / previous file (navigate is enabled) |
| `Space` / `q` | Page down / quit |

Want side-by-side? `git -c delta.side-by-side=true diff`, or set it permanently:
`git config --global delta.side-by-side true`.

### lazygit — git TUI

Run `lazygit` inside a repo.

| Key | Does |
|---|---|
| `Tab` or `1`–`5` | Move between panels (status/files/branches/commits/stash) |
| `Space` | Stage / unstage the selected file |
| `c` | Commit · `A` amend last commit |
| `p` / `P` | Pull / push |
| `?` | Context help (per panel) · `q` quit |

### PSReadLine predictions (Windows PowerShell)

As you type, greyed-out suggestions appear from history + plugins (ListView).

| Key | Does |
|---|---|
| `↑` / `↓` | Move through the suggestion list |
| `→` / `End` | Accept the whole suggestion |
| `Ctrl+→` | Accept the next word only |
| `F2` | Toggle inline ↔ list view |

Syntax colours are remapped onto the OneHalfDark palette in the same managed
profile block — PSReadLine's stock DarkGray parameters/operators are unreadable
on that background. Commands are blue, `-Parameters` cyan, strings green,
variables red. Edit the `Set-PSReadLineOption -Colors` hashtable in
`Ensure-PowerShellExperience` (setup-windows.ps1) and rerun setup to change
them — setup rewrites the block in place.

### zsh predictions (WSL)

The zsh counterpart of the PSReadLine block above — same keys, same idea.

| Key | Does |
|---|---|
| `→` / `End` | Accept the whole suggestion |
| `Ctrl+→` | Accept the next word only |
| `Ctrl+Space` | Accept (useful mid-line, where `→` just moves the cursor) |
| `Tab` | Accept the suggestion if one is showing, otherwise complete as usual |
| `↑` | Prefix-search history — type `git ` first and `↑` walks only your git commands |
| `Ctrl+R` | fzf history picker — the nearest thing zsh has to ListView |

- **zsh-autosuggestions** — greyed suggestion drawn from history, falling back to
  completion when history has no match.
- **zsh-syntax-highlighting** — commands turn **green** when valid, **red** when not,
  before you even press Enter. No keys — it's purely visual.

If the grey suggestion is invisible rather than absent, the colour is the problem,
not the plugin: the stock `fg=8` ("bright black") is within a shade of the
background on most WSL themes. Setup pins it to `#7f849c` via `ZSH_AUTOSUGGEST_COLOR`
in `setup-ubuntu.sh`. `bash audit-ubuntu.sh` flags the stock value as drift.

### Shell history (WSL)

Both shells keep **200 000** lines (`SHELL_HISTORY_SIZE` in `setup-ubuntu.sh`) and
flush after every command, so a killed terminal loses nothing. Out of the box zsh
keeps 1000 and oh-my-zsh raises `SAVEHIST` to only 10 000 — which silently
*truncates* `~/.zsh_history` on every write once you pass it.

The zsh settings are load-order sensitive and setup places them accordingly:
the `zsh history` block must sit **above** the oh-my-zsh source line (omz reassigns
`HISTSIZE`/`SAVEHIST`), and the `zsh history keys` block must sit **below** the fzf
integration (fzf binds `Tab`). The audit checks position, not just presence.

---

## Kubernetes quickies

| Tool | Use |
|---|---|
| `k9s` | Full-screen cluster TUI. `:pods`, `:svc`, `:deploy` to switch views; `?` help; `Ctrl+C` quit |
| `kubectx` | Switch cluster/context: `kubectx` (list/pick), `kubectx -` (previous) |
| `kubens` | Switch namespace: `kubens` (list/pick), `kubens -` (previous) |
| `stern` | Tail logs across many pods: `stern <name>`, `stern . -n <ns>`, `stern deploy/<name> --since 15m` |

---

## Configs & how to change defaults

| What | File | Note |
|---|---|---|
| WezTerm | `~/.wezterm.lua` (Windows home) | **Managed** — rewritten by `setup-windows.ps1`. For permanent changes edit the `WezTermConfig` block in that script, or accept that reruns overwrite hand edits. |
| Starship | `~/.config/starship.toml` (Windows **and** WSL, separately) | Never overwritten once it exists. |
| PowerShell profiles | `Documents\PowerShell\Microsoft.PowerShell_profile.ps1` (PS7) and `…\WindowsPowerShell\…` (PS5) | Starship init + the PSReadLine/PSFzf block live here. |
| Shell rc (WSL) | `~/.bashrc`, `~/.zshrc` | Starship, zoxide, fzf, and zsh plugin `source` lines are appended here. The history/prediction settings live in `# --- devbox: … ---` blocks that setup rewrites **in place** — edit `ensure_shell_history` in `setup-ubuntu.sh` and rerun, or your changes are overwritten. |

To reapply the whole setup, rerun `setup-windows.ps1` (as Admin) / `bash setup-ubuntu.sh` —
both are idempotent. To keep tools current, run `update-windows.ps1` / `bash update-ubuntu.sh`.

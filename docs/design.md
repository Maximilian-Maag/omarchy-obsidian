# omarchy-obsidian — design notes

## What the machine actually looks like

Discovered before writing any code (never guessed):

- Obsidian is installed at `/usr/bin/obsidian`.
- Obsidian records its vaults in `~/.config/obsidian/obsidian.json`:
  `{"vaults": {"<id>": {"path": "...", "ts": ..., "open": true}}}` — the real vault
  on this machine is `~/Documents/Obsidian Vault`, marked `open: true`.
- The vault's `.obsidian/core-plugins.json` has `"daily-notes": true`, but there is
  **no** `.obsidian/daily-notes.json`, so Obsidian's defaults apply: daily notes at
  the vault root, format `YYYY-MM-DD`.
- There is **no** `.obsidian/snippets/` directory yet — nothing loads custom CSS into
  Obsidian today.
- Omarchy already ships `~/.local/state/omarchy/current/theme/obsidian.css` (rendered
  from `/usr/share/omarchy/default/themed/obsidian.css.tpl`), **but Obsidian does not
  read that file.** Obsidian only loads CSS snippets from inside the vault. That gap
  is what the `theme` command closes.

## Vault discovery

`vault` reads `obsidian.json` verbatim. Selection order for a command that needs a
single vault: an explicit `--vault-path` wins; else `--vault <id|path|folder>`; else
the vault flagged `open`; else the first recorded. Nothing is inferred from the
filesystem.

## Daily notes

The path is `<vault>/<folder>/<date>.<format>.md`, where `folder` and `format` come
from the vault's `.obsidian/daily-notes.json` (defaults: root, `YYYY-MM-DD`).
Obsidian's `format` is a moment.js string; `moment_to_strftime` translates the common
tokens, longest-first so `MMMM` is never split by the `MM` rule (see the regression
test).

`capture` appends, creating the note with a `# YYYY-MM-DD` heading when missing. A
file that does not end in a newline gets one inserted first, so captures never glue
onto the previous line.

`today` opens the note with an `obsidian://open?vault=…&file=…` URI. The opener
program is configurable (`--opener`, or `OMARCHY_OBSIDIAN_OPENER`), which is how the
tests exercise the open path without a GUI.

## Theme snippet — no baked palette

`theme` reads `~/.local/state/omarchy/current/theme/colors.toml` (override with
`--colors`), maps its keys onto Obsidian's CSS variables, and writes
`<vault>/.obsidian/snippets/<name>.css` (default name `omarchy-theme`). Missing keys
fall back to **other theme keys**, never to a literal, so the plugin ships no colours
of its own. A regression test greps the CLI source for any `#RRGGBB` literal and
fails if one appears.

The snippet is written with `os.replace` over a `.tmp` file so a symlinked snippet
path swaps the link instead of overwriting its target (see the regression test).

## The theme-set hook, and the two hazards it avoids

- **Basename clobbering.** `omarchy hook install <type> <file>` installs the hook
  under the file's **basename**, so two plugins shipping `hooks/theme-set` install to
  the same path and the last wins silently. This plugin ships
  `hooks/obsidian-theme-set` and installs it under that name.
- **Self-location.** An installed hook cannot find its plugin relative to its own
  location — that path resolves to the hooks directory. The hook searches an
  `OMARCHY_OBSIDIAN_DIR` override, the installed plugin directory, then a dev
  checkout, and takes the first candidate that holds the CLI.

## Test layout

| Kind | File | What it covers |
|------|------|----------------|
| unit | `tests/test_unit_obsidian.py` | pure logic: vaults, daily paths, capture, colours, snippet, opener |
| regression | `tests/test_regression_obsidian.py` | one test per real bug class (hook clobber, self-locate, moment format, symlink write, no baked palette, `--no-create`) |
| integration | `tests/test_integration_cli.py` | the shipped CLI as a subprocess against a temp vault |
| e2e | `tests/e2e/test_obsidian.sh` | full round-trip on a synthetic vault, no GUI |
| shell | `tests/shell/test_theme_set.sh` | the real hook under a throwaway HOME with a fake plugin |
| mutation | `tests/mutation.json` | `bin/omarchy-obsidian` (python) + `hooks/obsidian-theme-set` (shell) |

All tests use temporary fixtures and a configurable vault path — nothing touches the
user's real notes, and no test launches the Obsidian GUI or the real `xdg-open`.

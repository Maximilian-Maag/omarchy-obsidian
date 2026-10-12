# Findings from building omarchy-obsidian

Concrete, machine-verified findings. These are the things that would cost time again.

## The vault layout is discoverable and must be read, not guessed

`~/.config/obsidian/obsidian.json` is the authoritative list:

```json
{"vaults":{"b0109111d5d5682f":{"path":"~/Documents/Obsidian Vault","ts":1791205724880,"open":true}}}
```

The `open` flag marks the vault the user last had open — a good default when the
command is given no explicit vault. Daily-note settings live in the vault at
`.obsidian/daily-notes.json`; when that file is **absent** the core plugin still runs
with defaults (root folder, `YYYY-MM-DD`). On this machine it is absent, so the plugin
must not require it to exist.

## Omarchy's theme `obsidian.css` is not read by Obsidian

`/usr/share/omarchy/default/themed/obsidian.css.tpl` is rendered into
`~/.local/state/omarchy/current/theme/obsidian.css` on every theme switch — and it is
dead weight as far as Obsidian is concerned, because Obsidian only loads CSS snippets
from `<vault>/.obsidian/snippets/`. The fix is to generate a *snippet* from the
applied `colors.toml`. The plugin therefore reads the same `colors.toml` the theme
system does, at runtime.

## `parse_colors` must not treat `#` as an inline comment

Omarchy's `colors.toml` uses `#` for comments **and** every colour value is a
`#RRGGBB` string. A naive `line.split("#", 1)[0]` strips the comment marker *and the
colour*, leaving an empty value — every colour silently disappears and the snippet is
blank. Verified live: the split form parsed `background = "#0B0C16"` to nothing. The
parser now only treats `#` as a comment at the **start of a line**. (Caught by the
integration/e2e tests as "carried no colours".)

## The theme-set hook: two hazards, both real

- **Basename clobbering (confirmed in the `omarchy-hook-install` source).**
  `HOOK_NAME=$(basename "$HOOK_FILE")`, so `hooks/theme-set` from two plugins
  installs to the same `~/.config/omarchy/hooks/theme-set.d/theme-set`. Ship a
  uniquely named file and install that. This plugin uses `obsidian-theme-set`.
- **Installed hooks cannot self-locate via `dirname $BASH_SOURCE`.** `omarchy-hook`
  runs each hook with `bash "$hook" "$@"` from the hooks directory, so any path
  derived from the hook's own location points at the hooks dir, not the plugin. The
  hook searches an override, the installed plugin dir, and a dev checkout instead.

## Mutation testing notes

- `per_operator: 6` and `max_mutants: 220` (per the project's standing rules) — the
  sample reaches the whole `bin/` target, not just the first occurrences of each
  operator.
- Two survivor classes had to be handled by **fixing the source**, not by declaring
  equivalence:
  - `note.parent.mkdir(parents=True, exist_ok=True)`: `parents=True -> False`
    survives unless a test builds into a **nested, not-yet-existing** directory. Fixed
    by giving the integration tests a nested daily folder (`Journal/2026`).
  - `if not line or line.startswith("#")`: the `or -> and` mutant survives unless a
    comment line contains `=`. Fixed by adding such a comment to the parse test.
- A bare numeric `return 1` in the shell `find_plugin` was **provably unobservable**
  (only its truthiness is read), so instead of declaring an equivalence the source was
  changed to `false` — removing the mutant outright. This is the preferred fix.
- **A mutant once caused a real hang.** In `open_uri` the chain
  `opener or env or "xdg-open"` mutated to `and` made a test fall through to the real
  `xdg-open`, which blocked on the live desktop for the 90 s timeout. The integration
  tests now put a harmless recorder script in `OMARCHY_OBSIDIAN_OPENER` for every test,
  so no mutant (or future test) can launch the real opener.

Final measured scores (see `tools/run_tests.sh`):

```
bin/omarchy-obsidian   37/37 killed  rate 1.00  (6 skipped, 0 timeout)
hooks/obsidian-theme-set 6/6 killed  rate 1.00  (0 skipped, 0 timeout)
```

## The `--date`/`--json` argparse gotcha

Global options must be declared *after* the verb to be usable there, or repeated on
each subparser. Re-declaring a shared option on both the top parser and a subparser
lets the subparser's default silently clobber a value given before the verb, so the
shared options (`--date`, `--json`) live on a `parents=[common]` subparser only.

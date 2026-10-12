# omarchy-obsidian

An [Omarchy](https://omarchy.org/) plugin that wires the **Obsidian** note app into
the desktop: it discovers the vaults Obsidian already knows, captures to and opens
today's daily note, and regenerates the vault's CSS snippet from the *applied*
Omarchy theme so notes follow the desktop palette.

## Why

Obsidian stores everything in a vault and knows exactly where it is
(`~/.config/obsidian/obsidian.json`), but the desktop has no idea. Omarchy themes
ship an `obsidian.css` in the theme directory, but Obsidian does not read that — it
only loads **CSS snippets from the vault**. `omarchy-obsidian` bridges both gaps
without guessing: it reads the real vault layout and the real applied palette.

## What it does

- **`vault`** — lists the vaults Obsidian knows (id, path, which one is open). The
  source of truth is `~/.config/obsidian/obsidian.json`; nothing is guessed.
- **`capture "text"`** — appends text to today's daily note, creating it with a
  `# YYYY-MM-DD` heading when it does not exist. The vault's own
  `.obsidian/daily-notes.json` **folder** and **moment format** are honoured.
- **`today`** — opens today's daily note via an `obsidian://open` URI
  (`--print` emits the URI instead; `--no-create` never writes a file).
- **`theme`** — reads the *applied* theme's
  `~/.local/state/omarchy/current/theme/colors.toml` at runtime and regenerates
  `<vault>/.obsidian/snippets/omarchy-theme.css`. **No colour palette is baked
  into this plugin** — every stock Omarchy theme works unchanged.
- **`bindings`** — prints the Hyprland keybinding module.

## Requirements

- Omarchy with Obsidian installed and at least one vault.
- Python 3 (system interpreter).

## Installation

```bash
omarchy plugin add https://github.com/Maximilian-Maag/omarchy-obsidian.git --enable
bash ~/.config/omarchy/plugins/Maximilian-Maag.obsidian/install.sh
```

Or from a clone: `bash install.sh`.

`install.sh` symlinks the CLI to `/usr/local/bin`, installs the **uniquely named**
`obsidian-theme-set` theme hook, wires the keybindings into Hyprland, and generates
the snippet for the currently applied theme.

## Usage

```bash
omarchy-obsidian vault                      # every vault Obsidian knows, * = open
omarchy-obsidian capture "buy milk"         # append to today's daily note
echo "from stdin" | omarchy-obsidian capture
omarchy-obsidian today                      # open today's note
omarchy-obsidian today --print              # just the obsidian:// URI
omarchy-obsidian theme                      # regenerate the vault snippet
omarchy-obsidian theme --print              # print the CSS without writing
omarchy-obsidian bindings                   # the Hyprland module
```

Select a vault explicitly with `--vault <id|path|folder>` or `--vault-path <dir>`,
and point at a different Obsidian config with `--obsidian-json <file>`.

## Keybindings

| Key | Action |
|-----|--------|
| `Super+Alt+N` | open today's daily note |
| `Super+Alt+C` | capture a one-line note (floating prompt) |
| `Super+Alt+T` | regenerate the vault snippet from the applied theme |

(`Super+Shift+O` still launches Obsidian itself, as Omarchy installs it.)

## How the theme snippet stays palette-free

`theme` parses the applied theme's `colors.toml` and maps its keys onto Obsidian's
CSS variables (`background`→`--background-primary`, `accent`→`--interactive-accent`,
`red`→`--text-title-h1`, …). Missing keys fall back to *other theme keys*, never to a
literal, so the plugin holds no colours of its own. The `theme-set` hook re-runs it
on every theme switch.

## Development

```bash
make check     # policy + unit + regression (fast)
make test      # full suite incl. e2e, shell and mutation
SKIP_MUTATION=1 make test
```

See `docs/` for the design notes and the findings from building this plugin.

## License

MIT — see `LICENSE`.

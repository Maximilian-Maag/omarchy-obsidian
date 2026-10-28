# Changelog

All notable changes to omarchy-obsidian are documented here.

## [0.1.1] — 2026-10-28

### Fixed
- **The `theme` command labelled the applied theme as literally "theme"** (#1). It took
  the colors path's parent directory name, but the applied `colors.toml` is a copy under a
  fixed `theme` directory, so the name is never in the path — the generated snippet carried
  `Applied theme: theme` (and `install.sh` produced one too). `theme` now recovers the name
  the theme-set hook recorded (`<state>/omarchy-obsidian/active-theme`), then falls back to
  matching the applied colours against the installed theme dirs — exactly what the sibling
  plugins (docker/mpv/tmux resolve, voxtype records) do — and shows `(unknown)` rather than
  the misleading directory name.

## [0.1.0] — 2026-10-12

### Added
- **Vault discovery.** `omarchy-obsidian vault` reads the vaults Obsidian already
  knows from `~/.config/obsidian/obsidian.json` (path, id, which one is open) —
  it never guesses a location. `--vault` selects one by id, path or folder name.
- **Daily-note capture.** `omarchy-obsidian capture "text"` appends to today's
  daily note, creating it with a `# YYYY-MM-DD` heading when it does not exist.
  The vault's own `.obsidian/daily-notes.json` folder and moment-format are
  honoured (default: vault root, `YYYY-MM-DD`).
- **Open today's note.** `omarchy-obsidian today` hands an `obsidian://open` URI
  to the desktop opener (`--print` emits the URI instead; `--opener` overrides
  the program, so it is testable without a GUI).
- **Theme-aware vault snippet.** `omarchy-obsidian theme` reads the *applied*
  Omarchy theme's `colors.toml` at runtime and regenerates
  `.obsidian/snippets/omarchy-theme.css` inside the vault — no colour palette is
  baked into the plugin, so all stock themes work unchanged.
- **Hyprland keybindings** for today's note (`Super+Alt+N`), a capture prompt
  (`Super+Alt+C`) and a theme refresh (`Super+Alt+T`).
- **Uniquely named `theme-set` hook** (`hooks/obsidian-theme-set`) that
  self-locates the plugin, so installing it cannot clobber another plugin's
  `theme-set` hook and it still finds its CLI once installed.
- Full test harness: unit, regression, integration, e2e, shell and mutation
  kinds, all run from `make test` (or `tools/run_tests.sh`), plus policy as code.

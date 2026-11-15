#!/bin/bash
# omarchy-obsidian install script. Run once after cloning, or re-run to update.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "omarchy-obsidian: installing from $PLUGIN_DIR"

# ── 1. Validate the plugin ────────────────────────────────────────────────────
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$PLUGIN_DIR" && echo "  manifest OK."
fi

# ── 2. Put the CLI on PATH (symlink, so git pull keeps it current) ────────────
BIN_SRC="$PLUGIN_DIR/bin/omarchy-obsidian"
BIN_DEST="/usr/local/bin/omarchy-obsidian"
chmod +x "$BIN_SRC"
if [[ -L "$BIN_DEST" ]] && [[ "$(readlink -f "$BIN_DEST")" == "$(readlink -f "$BIN_SRC")" ]]; then
  echo "  omarchy-obsidian already on PATH."
elif (( EUID == 0 )); then
  ln -sf "$BIN_SRC" "$BIN_DEST" && echo "  Installed $BIN_DEST."
elif command -v sudo >/dev/null 2>&1; then
  sudo ln -sf "$BIN_SRC" "$BIN_DEST" && echo "  Installed $BIN_DEST."
else
  echo "  WARNING: no sudo — add $BIN_SRC to PATH manually."
fi

# ── 3. Theme-set hook (uniquely named so it cannot clobber another plugin's) ──
chmod +x "$PLUGIN_DIR/hooks/obsidian-theme-set"
if command -v omarchy >/dev/null 2>&1; then
  omarchy hook install theme-set "$PLUGIN_DIR/hooks/obsidian-theme-set"
  echo "  Installed theme-set hook (obsidian-theme-set)."
fi

# ── 4. Wire keybindings into Hyprland ─────────────────────────────────────────
HYPR_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
HYPR_MAIN="$HYPR_CONFIG_DIR/hyprland.lua"
if [[ -f "$HYPR_MAIN" ]]; then
  cp "$PLUGIN_DIR/bin/bindings.lua" "$HYPR_CONFIG_DIR/obsidian-bindings.lua"
  if ! grep -q "obsidian-bindings" "$HYPR_MAIN"; then
    printf '\n-- omarchy-obsidian keybindings\nrequire("hypr.obsidian-bindings")\n' >> "$HYPR_MAIN"
    echo "  Wired keybindings into $HYPR_MAIN"
  else
    echo "  Keybindings already wired (updated)."
  fi
else
  echo "  WARNING: $HYPR_MAIN not found — add: require(\"hypr.obsidian-bindings\")"
fi

# ── 5. Generate the snippet for the currently applied theme ───────────────────
# Call the CLI by its absolute checkout path, not by name: a failed step-2
# symlink (no sudo, /usr/local/bin not on PATH) must not silently skip snippet
# generation and still exit 0 (#5).
if "$BIN_SRC" theme; then
  echo "  Wrote the vault CSS snippet."
else
  echo "  WARNING: could not generate the vault CSS snippet — run 'omarchy-obsidian theme' later."
fi

echo ""
echo "Done. Try:  omarchy-obsidian vault   /   omarchy-obsidian today   /   omarchy-obsidian capture 'hello'"

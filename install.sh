#!/bin/bash
# omarchy-obsidian install script. Run once after cloning, or re-run to update.
#
#   ./install.sh                     install / update everything
#   ./install.sh --uninstall         remove what this script installed, and only that
#   OMARCHY_OBSIDIAN_BIN=~/.local/bin ./install.sh   where the CLI is symlinked
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_SRC="$PLUGIN_DIR/bin/omarchy-obsidian"
# Where the CLI is symlinked. Defaults to /usr/local/bin (the Omarchy convention);
# the override lets a user install into their own bin directory, and lets the
# tests exercise the symlink install/uninstall without root.
BIN_DIR="${OMARCHY_OBSIDIAN_BIN:-/usr/local/bin}"
BIN_DEST="$BIN_DIR/omarchy-obsidian"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
HYPR_DIR="$CONFIG_DIR/hypr"
HYPR_MAIN="$HYPR_DIR/hyprland.lua"
FRAGMENT="$HYPR_DIR/obsidian-bindings.lua"
REQUIRE_LINE='require("hypr.obsidian-bindings")'
MARKER='-- omarchy-obsidian keybindings'
HOOK_DEST="$CONFIG_DIR/omarchy/hooks/theme-set.d/obsidian-theme-set"
# The first line of the module install copies; the uninstall uses it to decide
# that a file at FRAGMENT is ours (and not something the user wrote).
FRAGMENT_MARKER='-- Hyprland keybindings added by omarchy-obsidian.'

say() { echo "  $1"; }
warn() { echo "WARNING: $1" >&2; }

link_cli() {
  chmod +x "$BIN_SRC"
  mkdir -p "$(dirname "$BIN_DEST")" 2>/dev/null || true
  if [[ -L "$BIN_DEST" ]] && [[ "$(readlink -f "$BIN_DEST")" == "$(readlink -f "$BIN_SRC")" ]]; then
    say "omarchy-obsidian already on PATH."
  elif (( EUID == 0 )) || [[ -w "$(dirname "$BIN_DEST")" ]]; then
    ln -sf "$BIN_SRC" "$BIN_DEST" && say "Installed $BIN_DEST."
  elif command -v sudo >/dev/null 2>&1; then
    sudo ln -sf "$BIN_SRC" "$BIN_DEST" && say "Installed $BIN_DEST."
  else
    warn "no sudo — add $BIN_SRC to PATH manually."
  fi
}

unlink_ours() {  # unlink_ours <path> <source it must point at>
  local dest="$1" source="$2"
  if [[ -L "$dest" ]] && [[ "$(readlink -f "$dest")" == "$(readlink -f "$source")" ]]; then
    if (( EUID == 0 )) || [[ -w "$(dirname "$dest")" ]]; then
      rm -f "$dest"
    elif command -v sudo >/dev/null 2>&1; then
      sudo rm -f "$dest"
    else
      warn "could not remove $dest — no permission and no sudo."
      return 0
    fi
    say "removed $dest"
  elif [[ -e "$dest" ]]; then
    warn "$dest is not a link into this checkout — left alone."
  fi
}

remove_require_block() {
  [[ -f "$HYPR_MAIN" ]] || return 0
  grep -qF "$REQUIRE_LINE" "$HYPR_MAIN" || return 0
  # Rebuilt line by line (never `sed -i`): the require line came in as a block —
  # a blank line, the `-- omarchy-obsidian keybindings` marker, then the line —
  # so the whole block goes back out, leaving no marker to stack up next time.
  local out=() line
  mapfile -t lines < "$HYPR_MAIN"
  for line in "${lines[@]}"; do
    if [[ $line == "$REQUIRE_LINE" ]]; then
      if (( ${#out[@]} )) && [[ ${out[-1]} == "$MARKER" ]]; then
        unset 'out[-1]'
        if (( ${#out[@]} )) && [[ -z ${out[-1]} ]]; then
          unset 'out[-1]'
        fi
      fi
      continue
    fi
    out+=("$line")
  done
  kept="$(mktemp)"
  for line in ${out[@]+"${out[@]}"}; do
    printf '%s\n' "$line"
  done > "$kept"
  mv "$kept" "$HYPR_MAIN"
  say "took the require line back out of $HYPR_MAIN"
}

# Reverses what `omarchy-obsidian theme` writes into the vault: the generated CSS
# snippet and its `enabledCssSnippets` entry. The vault is resolved through the
# CLI itself (the same selection logic the install used) rather than re-derived
# here, so the two can never drift.
remove_vault_snippet() {
  command -v python3 >/dev/null 2>&1 || { warn "python3 not found — the vault snippet was left in place."; return 0; }
  python3 - "$BIN_SRC" "${OBSIDIAN_JSON:-}" <<'PY'
import importlib.machinery
import importlib.util
import sys

cli, obsidian_json = sys.argv[1], sys.argv[2]
loader = importlib.machinery.SourceFileLoader("_omarchy_obsidian_cli", cli)
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

cfg = module._load_plugin_config(None)
json_path = module.expand(obsidian_json) if obsidian_json else module.expand(module.DEFAULT_OBSIDIAN_JSON)
chosen = module.select_vault(module.list_vaults(json_path), cfg.get("vault"))
if chosen is None:
    print("omarchy-obsidian: no vault to clean up")
    raise SystemExit(0)

vault = module.expand(chosen["path"])
name = cfg.get("snippet") or module.DEFAULT_SNIPPET
css = module.snippet_path(vault, name)
if css.is_file():
    css.unlink()
    print("omarchy-obsidian: removed %s" % css)

appearance = module.appearance_path(vault)
data = module.read_json(appearance, {})
enabled = data.get("enabledCssSnippets") if isinstance(data, dict) else None
if isinstance(enabled, list) and name in enabled:
    data["enabledCssSnippets"] = [s for s in enabled if s != name]
    if not data["enabledCssSnippets"] and set(data) <= {"enabledCssSnippets"}:
        # The installer created appearance.json for this snippet alone; undo that.
        appearance.unlink()
        print("omarchy-obsidian: removed %s" % appearance)
    else:
        module.write_json_atomic(appearance, data)
        print("omarchy-obsidian: removed %s from %s" % (name, appearance))
PY
}

uninstall() {
  echo "omarchy-obsidian: uninstalling"

  # 1. The CLI symlink, and only when it points into this checkout.
  unlink_ours "$BIN_DEST" "$BIN_SRC"

  # 2. The theme-set hook.
  if [[ -f "$HOOK_DEST" ]]; then
    rm -f "$HOOK_DEST"
    say "removed the theme-set hook"
  fi

  # 3. The copied keybinding module (ours: it carries our header) and the
  #    require block install appended.
  if [[ -f "$FRAGMENT" ]] && head -1 "$FRAGMENT" | grep -qF -- "$FRAGMENT_MARKER"; then
    rm -f "$FRAGMENT"
    say "removed $FRAGMENT"
  elif [[ -e "$FRAGMENT" ]]; then
    warn "$FRAGMENT is not ours — left alone."
  fi
  remove_require_block

  # 4. Anything install wrote into the vault.
  remove_vault_snippet

  echo ""
  echo "Done. Reload Hyprland config:  hyprctl reload"
}

if [[ ${1:-} == --uninstall ]]; then
  uninstall
  exit 0
fi

echo "omarchy-obsidian: installing from $PLUGIN_DIR"

# ── 1. Validate the plugin ────────────────────────────────────────────────────
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$PLUGIN_DIR" && echo "  manifest OK."
fi

# ── 2. Put the CLI on PATH (symlink, so git pull keeps it current) ────────────
link_cli

# ── 3. Theme-set hook (uniquely named so it cannot clobber another plugin's) ──
chmod +x "$PLUGIN_DIR/hooks/obsidian-theme-set"
if command -v omarchy >/dev/null 2>&1; then
  omarchy hook install theme-set "$PLUGIN_DIR/hooks/obsidian-theme-set"
  echo "  Installed theme-set hook (obsidian-theme-set)."
fi

# ── 4. Wire keybindings into Hyprland ─────────────────────────────────────────
if [[ -f "$HYPR_MAIN" ]]; then
  cp "$PLUGIN_DIR/bin/bindings.lua" "$FRAGMENT"
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
echo "Remove it all again with:  ./install.sh --uninstall"

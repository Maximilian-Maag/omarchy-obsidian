#!/bin/bash
# Round-trip test for `install.sh --uninstall`.
#
# The contract: an install followed by an uninstall leaves the user's own config
# byte-identical (sha256) and removes EXACTLY what the install added — the CLI
# symlink, the theme-set hook, the copied keybinding module and the require
# block, and anything written into the vault (the generated CSS snippet and its
# `enabledCssSnippets` entry) — while leaving anything that is not ours alone.
#
# Hermetic: a throwaway HOME/XDG with stubbed omarchy/sudo, and the CLI symlinked
# into the sandbox (OMARCHY_OBSIDIAN_BIN) so no root is involved.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$ROOT/install.sh"
pass=0; fail=0
ok()  { echo "  ok: $*"; pass=$((pass+1)); }
bad() { echo "  FAIL: $*"; fail=$((fail+1)); }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
export XDG_STATE_HOME="$SANDBOX/state"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$SANDBOX/data"
export OMARCHY_OBSIDIAN_BIN="$SANDBOX/bin"
VAULT="$SANDBOX/vault"
mkdir -p "$XDG_CONFIG_HOME/hypr" "$XDG_CONFIG_HOME/omarchy/hooks/theme-set.d" \
         "$XDG_CONFIG_HOME/obsidian" "$HOME/.local/state/omarchy/current/theme" \
         "$XDG_DATA_HOME" "$OMARCHY_OBSIDIAN_BIN" "$VAULT/.obsidian"
cat > "$HOME/.local/state/omarchy/current/theme/colors.toml" <<'TOML'
mode = "dark"
accent = "#82FB9C"
selection = "#1f253a"
muted = "#2d3450"
background = "#0B0C16"
foreground = "#ddf7ff"
red = "#ff0000"
green = "#00ff00"
yellow = "#ffff00"
blue = "#0000ff"
magenta = "#ff00ff"
cyan = "#00ffff"
TOML
# The CLI's default obsidian.json path is ~/.config/obsidian/obsidian.json.
cat > "$XDG_CONFIG_HOME/obsidian/obsidian.json" <<JSON
{ "vaults": { "v1": { "path": "$VAULT", "open": true } } }
JSON

# Stubbed omarchy/sudo first on PATH; a real python3 (for the CLI) after them.
STUB="$SANDBOX/stub"; mkdir -p "$STUB"
export PATH="$STUB:/usr/bin:/bin:/usr/local/bin"
printf '#!/bin/bash\nexit 0\n' > "$STUB/omarchy"
printf '#!/bin/bash\nexit 0\n' > "$STUB/sudo"
chmod +x "$STUB/omarchy" "$STUB/sudo"

HYPR="$XDG_CONFIG_HOME/hypr/hyprland.lua"
FRAGMENT="$XDG_CONFIG_HOME/hypr/obsidian-bindings.lua"
HOOK="$XDG_CONFIG_HOME/omarchy/hooks/theme-set.d/obsidian-theme-set"
CLI_LINK="$OMARCHY_OBSIDIAN_BIN/omarchy-obsidian"
SNIPPET="$VAULT/.obsidian/snippets/omarchy-theme.css"
APPEARANCE="$VAULT/.obsidian/appearance.json"

sha() { sha256sum "$1" | cut -d' ' -f1; }
setup_user() {
  printf -- '-- main config\nlocal monitors = {}\n' > "$HYPR"
  printf '#!/bin/bash\n' > "$HOOK"
  rm -f "$APPEARANCE"
}

echo "install/uninstall round-trip"

# ── 1. The happy path: byte-identity plus removal of every artifact. ──────────
setup_user
before_hypr="$(sha "$HYPR")"

if bash "$INSTALL" >"$SANDBOX/install.log" 2>&1; then ok "install exit 0"; else bad "install failed"; cat "$SANDBOX/install.log"; fi
if [[ -L "$CLI_LINK" ]]; then ok "install symlinked the CLI"; else bad "no CLI symlink"; fi
if [[ -f "$FRAGMENT" ]]; then ok "install copied the bindings module"; else bad "no bindings module"; fi
if grep -qF 'require("hypr.obsidian-bindings")' "$HYPR"; then ok "install wired the require line"; else bad "no require line"; fi
if [[ -f "$SNIPPET" ]]; then ok "install generated the vault snippet"; else bad "no vault snippet"; cat "$SANDBOX/install.log"; fi
if grep -q '"omarchy-theme"' "$APPEARANCE" 2>/dev/null; then ok "install enabled the snippet"; else bad "snippet not enabled"; fi

if bash "$INSTALL" --uninstall >"$SANDBOX/uninstall.log" 2>&1; then ok "uninstall exit 0"; else bad "uninstall failed"; cat "$SANDBOX/uninstall.log"; fi
if [[ "$(sha "$HYPR")" == "$before_hypr" ]]; then ok "hyprland.lua is byte-identical after the round-trip"; else bad "hyprland.lua changed"; cat "$HYPR"; fi
if [[ "$(grep -c -- '-- omarchy-obsidian' "$HYPR")" == 0 ]]; then ok "no marker comment left in hyprland.lua"; else bad "a marker was left behind"; cat "$HYPR"; fi
if [[ ! -e "$CLI_LINK" ]]; then ok "removed the CLI symlink"; else bad "CLI symlink survived"; fi
if [[ ! -e "$FRAGMENT" ]]; then ok "removed the bindings module"; else bad "bindings module survived"; fi
if [[ ! -e "$HOOK" ]]; then ok "removed the theme-set hook"; else bad "hook survived"; fi
if [[ ! -e "$SNIPPET" ]]; then ok "removed the vault snippet"; else bad "vault snippet survived"; fi
if [[ ! -e "$APPEARANCE" ]]; then ok "removed the appearance.json it created"; else bad "appearance.json was left behind"; cat "$APPEARANCE"; fi

# ── 2. A second cycle stays byte-identical (no marker accumulation). ──────────
bash "$INSTALL" >/dev/null 2>&1
bash "$INSTALL" --uninstall >/dev/null 2>&1
if [[ "$(sha "$HYPR")" == "$before_hypr" && ! -e "$SNIPPET" ]]; then
  ok "a second install/uninstall cycle stays byte-identical"
else
  bad "a second cycle changed things"; cat "$HYPR"
fi

# ── 3. A hand-added require line (no marker) is removed, its neighbour kept. ──
printf 'local monitors = {}\nrequire("hypr.obsidian-bindings")\n' > "$HYPR"
bash "$INSTALL" --uninstall >/dev/null 2>&1
if [[ "$(cat "$HYPR")" == 'local monitors = {}' ]]; then
  ok "a hand-added require line is removed without eating the line above it"
else
  bad "hand-added require line handling is wrong"; cat "$HYPR"
fi

# ── 4. A user's own appearance.json survives: only our entry is taken out. ─────
printf '{\n  "cssTheme": "obsidian",\n  "enabledCssSnippets": ["my-own"]\n}\n' > "$APPEARANCE"
printf -- '-- main\n' > "$HYPR"
bash "$INSTALL" >/dev/null 2>&1
if grep -q '"my-own"' "$APPEARANCE" && grep -q '"omarchy-theme"' "$APPEARANCE"; then
  ok "install added its snippet beside the user's own"
else
  bad "install did not add its snippet to a pre-existing appearance.json"; cat "$APPEARANCE"
fi
bash "$INSTALL" --uninstall >/dev/null 2>&1
if grep -q '"my-own"' "$APPEARANCE" && ! grep -q '"omarchy-theme"' "$APPEARANCE" && grep -q '"cssTheme"' "$APPEARANCE"; then
  ok "the user's own appearance.json survived, minus our entry"
else
  bad "the user's appearance.json was not restored correctly"; cat "$APPEARANCE"
fi

# ── 5. A foreign symlink at the CLI path is left alone. ───────────────────────
printf -- '-- main\n' > "$HYPR"
ln -sfn /bin/true "$CLI_LINK"
out="$(bash "$INSTALL" --uninstall 2>&1)"; rc=$?
if (( rc == 0 )); then ok "an uninstall over a foreign symlink exits 0"; else bad "uninstall exit $rc"; fi
if [[ -L "$CLI_LINK" ]] && [[ "$(readlink "$CLI_LINK")" == "/bin/true" ]]; then
  ok "a foreign symlink at the CLI path is left alone"
else
  bad "a foreign symlink was removed"; ls -l "$CLI_LINK" 2>&1
fi
if [[ $out == *"not a link into this checkout"* ]]; then ok "and the uninstall says why"; else bad "no reason given: $out"; fi
rm -f "$CLI_LINK"

# ── 6. Uninstalling nothing is not an error. ──────────────────────────────────
bash "$INSTALL" --uninstall >/dev/null 2>&1
if (( $? == 0 )); then ok "uninstalling an empty machine succeeds"; else bad "uninstalling nothing failed"; fi

echo
if (( fail == 0 )); then echo "shell: all $pass passed"; exit 0; else echo "shell: $fail failed"; exit 1; fi

#!/bin/bash
# Shell tests for omarchy-obsidian's install.sh — hermetic (throwaway HOME/XDG,
# stubbed omarchy/sudo). The key guarantee (#5): the snippet step runs the CLI by
# its absolute checkout path, so a failed symlink step cannot silently skip
# snippet generation while the installer still exits 0.
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
export XDG_CONFIG_HOME="$SANDBOX/home/.config"
export XDG_DATA_HOME="$SANDBOX/data"
VAULT="$SANDBOX/vault"
mkdir -p "$HOME/.local/state/omarchy/current/theme" "$XDG_CONFIG_HOME/obsidian" "$VAULT" "$XDG_DATA_HOME"
cat > "$HOME/.local/state/omarchy/current/theme/colors.toml" <<'TOML'
mode = "dark"
accent = "#82FB9C"
selection = "#1f253a"
muted = "#2d3450"
background = "#0B0C16"
foreground = "#ddf7ff"
TOML
cat > "$XDG_CONFIG_HOME/obsidian/obsidian.json" <<JSON
{ "vaults": { "v1": { "path": "$VAULT", "open": true } } }
JSON

# Stub omarchy + sudo. The sudo stub deliberately does NOT create the
# /usr/local/bin symlink, and /usr/local/bin is excluded from PATH, so the old
# `command -v omarchy-obsidian` guard would have skipped snippet generation.
BIN="$SANDBOX/bin"; mkdir -p "$BIN"
printf '#!/bin/bash\nexit 0\n' > "$BIN/omarchy"
printf '#!/bin/bash\nexit 0\n' > "$BIN/sudo"
chmod +x "$BIN/omarchy" "$BIN/sudo"
export PATH="$BIN:/usr/bin:/bin"

bash "$INSTALL" >"$SANDBOX/install.log" 2>&1
rc=$?
if (( rc == 0 )); then ok "install.sh exit 0"; else bad "install.sh exit $rc"; cat "$SANDBOX/install.log"; fi

if [[ -f "$VAULT/.obsidian/snippets/omarchy-theme.css" ]]; then
  ok "snippet generated via the absolute CLI path"
else
  bad "snippet NOT generated (the #5 regression)"; cat "$SANDBOX/install.log"
fi
if grep -q '"omarchy-theme"' "$VAULT/.obsidian/appearance.json" 2>/dev/null; then
  ok "snippet enabled in appearance.json"
else
  bad "snippet not enabled in appearance.json"
fi
if grep -qi "command -v omarchy-obsidian" "$INSTALL"; then
  bad "install.sh still guards the snippet step with command -v omarchy-obsidian"
else
  ok "install.sh calls the CLI by its absolute path (no command -v guard)"
fi

echo
if (( fail == 0 )); then echo "shell: all $pass passed"; exit 0; else echo "shell: $fail failed"; exit 1; fi

#!/bin/bash
# e2e: build a synthetic vault + obsidian.json + colors.toml, then drive the shipped
# CLI against it and assert the real on-disk effect. No GUI is launched, and the
# user's real vault is never touched.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT/bin/omarchy-obsidian"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

VAULT="$WORK/vault"
mkdir -p "$VAULT/.obsidian"

cat > "$WORK/obsidian.json" <<JSON
{"vaults": {"e2e": {"path": "$VAULT", "open": true}}}
JSON

cat > "$WORK/colors.toml" <<'TOML'
mode = "dark"
accent = "#82FB9C"
selection = "#1f253a"
muted = "#2d3450"
background = "#0B0C16"
foreground = "#ddf7ff"
red = "#50f872"
green = "#4fe88f"
yellow = "#50f7d4"
blue = "#829dd4"
magenta = "#86a7df"
cyan = "#7cf8f7"
TOML

run() { "$CLI" --obsidian-json "$WORK/obsidian.json" --config "$WORK/cfg.json" "$@"; }

# 1. discover the vault
if run vault --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d)==1 and d[0]["id"]=="e2e"'; then
  echo "e2e: ok — vault discovered"
else
  echo "e2e: FAILED — vault not discovered" >&2; exit 1
fi

# 2. capture creates today's note
run capture --date 2026-10-12 "e2e note" >/dev/null
NOTE="$VAULT/2026-10-12.md"
if [[ -f "$NOTE" ]] && grep -q "e2e note" "$NOTE"; then
  echo "e2e: ok — capture wrote $NOTE"
else
  echo "e2e: FAILED — capture wrote nothing" >&2; exit 1
fi

# 3. theme regenerates the vault snippet from the applied palette
run theme --colors "$WORK/colors.toml" --theme "Hackerman" >/dev/null
SNIP="$VAULT/.obsidian/snippets/omarchy-theme.css"
if [[ -f "$SNIP" ]] && grep -q -- "--background-primary: #0B0C16;" "$SNIP"; then
  echo "e2e: ok — theme snippet generated from the applied palette"
else
  echo "e2e: FAILED — snippet missing or wrong palette" >&2; exit 1
fi

echo "e2e: all checks passed"

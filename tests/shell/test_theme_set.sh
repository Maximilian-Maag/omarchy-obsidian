#!/bin/bash
# Shell tests for hooks/obsidian-theme-set — run hermetically with a throwaway
# HOME/XDG, and a fake plugin that records being invoked.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/hooks/obsidian-theme-set"
pass=0; fail=0
ok()  { echo "  ok: $*"; pass=$((pass+1)); }
bad() { echo "  FAIL: $*"; fail=$((fail+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sandbox() {
  export HOME="$WORK/home-$1"
  export XDG_STATE_HOME="$HOME/.local/state"
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$HOME"
  unset OMARCHY_OBSIDIAN_DIR
  unset OBSIDIAN_MARKER
}

# A fake plugin whose CLI records the arguments it is handed.
FAKE="$WORK/fake-plugin"
mkdir -p "$FAKE/bin"
cat > "$FAKE/bin/omarchy-obsidian" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$OBSIDIAN_MARKER"
STUB
chmod +x "$FAKE/bin/omarchy-obsidian"

# 1. a theme name writes the normalised state file AND invokes the plugin CLI
sandbox 1
export OMARCHY_OBSIDIAN_DIR="$FAKE"
export OBSIDIAN_MARKER="$WORK/marker1"
bash "$HOOK" "Tokyo Night"
rc=$?
STATE="$XDG_STATE_HOME/omarchy-obsidian/active-theme"
if (( rc == 0 )); then
  ok "hook exits 0 on a real theme"
else
  bad "hook exit status wrong (rc=$rc)"
fi
if [[ -f "$STATE" && "$(cat "$STATE")" == "tokyo-night" ]]; then
  ok "theme written normalised"
else
  bad "theme state file wrong (got: $(cat "$STATE" 2>/dev/null))"
fi
if [[ -f "$OBSIDIAN_MARKER" ]] && grep -q -- "--theme tokyo-night" "$OBSIDIAN_MARKER"; then
  ok "plugin CLI invoked with the slugged theme"
else
  bad "plugin CLI was not invoked (marker: $(cat "$OBSIDIAN_MARKER" 2>/dev/null))"
fi

# 2. no argument is a no-op: nothing written, plugin not invoked, exit 0
sandbox 2
export OMARCHY_OBSIDIAN_DIR="$FAKE"
export OBSIDIAN_MARKER="$WORK/marker2"
bash "$HOOK"
rc=$?
if [[ ! -e "$XDG_STATE_HOME/omarchy-obsidian/active-theme" && ! -e "$OBSIDIAN_MARKER" && "$rc" == "0" ]]; then
  ok "empty theme is a full no-op (exit 0)"
else
  bad "empty theme: state/marker written or wrong exit (rc=$rc)"
fi

# 3. with no plugin discoverable the hook still stamps state and exits 0
sandbox 3
bash "$HOOK" "Hackerman"
STATE3="$XDG_STATE_HOME/omarchy-obsidian/active-theme"
if [[ -f "$STATE3" && "$(cat "$STATE3")" == "hackerman" ]]; then
  ok "state stamped even when no plugin is found"
else
  bad "state not stamped without a plugin (got: $(cat "$STATE3" 2>/dev/null))"
fi

# 4. the hook never assumes its plugin lives at $(dirname $BASH_SOURCE)/..
if grep -q 'dirname' "$HOOK"; then
  bad "hook still relies on dirname \$BASH_SOURCE"
else
  ok "hook self-locates (no dirname-based plugin path)"
fi

# 5. the shipped Lua module keeps its bindings
LUA="$ROOT/bin/bindings.lua"
if grep -q 'o.bind' "$LUA" && grep -q 'omarchy-obsidian' "$LUA"; then
  ok "bindings.lua declares keybindings for the CLI"
else
  bad "bindings.lua missing bindings"
fi

echo
if (( fail == 0 )); then echo "shell: all $pass passed"; exit 0; else echo "shell: $fail failed"; exit 1; fi

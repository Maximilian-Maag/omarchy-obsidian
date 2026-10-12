-- Hyprland keybindings added by omarchy-obsidian.
-- Install.sh copies this to ~/.config/hypr/obsidian-bindings.lua and adds
--   require("hypr.obsidian-bindings")
-- to ~/.config/hypr/hyprland.lua.
--
-- Super+Shift+O already launches Obsidian (installed by Omarchy itself); these
-- keys add daily-note access on top of it. The org.omarchy.* app-id makes
-- Omarchy auto-float the helper window.

-- Open today's daily note.
hl.unbind("SUPER + ALT + N")
o.bind("SUPER + ALT + N", "Obsidian: today's note", "omarchy-obsidian today")

-- Capture a one-line thought into today's daily note (floating prompt).
hl.unbind("SUPER + ALT + C")
o.bind("SUPER + ALT + C", "Obsidian: capture", {
  app_id = "org.omarchy.obsidian",
  launch = "xdg-terminal-exec --app-id=org.omarchy.obsidian --title='Obsidian capture' -- "
    .. "bash -c 'read -r -p \"Note: \" t; omarchy-obsidian capture \"$t\"'",
})

-- Regenerate the vault CSS snippet from the applied theme.
hl.unbind("SUPER + ALT + T")
o.bind("SUPER + ALT + T", "Obsidian: refresh theme", "omarchy-obsidian theme")

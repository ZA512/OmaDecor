# Native Decoration Renderer

This Hyprland plugin compiles bounded `*.omadecor.json` recipes and renders
their V1 Core operations inside the compositor. It targets Hyprland `0.56.2`
and must be rebuilt for the exact Hyprland ABI in use. The native build also
requires `json-c`.

Build it with:

```bash
make -C native
```

For development, load the resulting absolute path with `hyprctl plugin load`. The stock Hyprland border must be set to `0` while this decoration is enabled, otherwise both native decorations are intentionally rendered. Manual loading is session-only; release installs should use `hyprpm` so the plugin is rebuilt for Hyprland updates.

Example Lua configuration:

```lua
hl.config({
  general = { border_size = 0 },
  plugin = {
    omadecor = {
      enabled = true,
      light_width = 2,
      dark_width = 5,
      shade_factor = 0.45,
      inactive_opacity = 0.55,
      theme_path = "/absolute/path/to/raised-edge.omadecor.json",
      excluded_classes = "steam,org.gnome.Calculator",
      col = {
        active = "rgb(47d7ff)",
        inactive = "rgb(64748b)",
      },
    },
  },
})
```

To end a manual test, unload the same absolute path and run `hyprctl reload` to restore the user's configured stock border.

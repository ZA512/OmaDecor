# OmaDecor

OmaDecor adds compositor-synchronized window decoration and an optional
click-through HUD to Omarchy. Its settings panel keeps Decorations, HUD, and
Effects independently configurable.

The current development baseline is Omarchy with Hyprland 0.56.2 and
Quickshell 0.3.1. Hyprland plugins are ABI-sensitive: rebuild the native
component after every Hyprland update.

## Status

- **Decorations:** native Raised Edge renderer, configuration, fullscreen
  suppression, and per-application exclusions are implemented.
- **HUD:** window title/workspace and system metrics are implemented. It hides
  while the active window moves or resizes, then reappears after settling.
- **Effects:** HyprWindowShade detection, compatibility suspension, event
  mapping, per-application exclusions/overrides, and owned-rule generation are
  implemented. The external engine is never installed automatically.

## Install from GitHub

Install the Omarchy interface and the native Hyprland component separately:

```bash
omarchy plugin add https://github.com/ZA512/OmaDecor.git --enable --yes
hyprpm add https://github.com/ZA512/OmaDecor.git
hyprpm enable omadecor-native
hyprpm reload
omarchy bar put omadecor --section right
```

If `hyprpm` needs system headers on its first run, execute its commands in an
interactive terminal and follow its prompt. Do not load a binary built for a
different Hyprland version.

Click **OD** in the bar to open settings. Middle-click refreshes diagnostics;
right-click opens application exclusions. If the widget was installed before
bar support was added, refresh it with:

```bash
omarchy plugin update omadecor
omarchy plugin enable omadecor
omarchy bar put omadecor --section right
omarchy restart shell
```

### Optional window effects

Install the external engine in an interactive terminal:

```bash
hyprpm add https://github.com/ManofJELLO/HyprWindowShade
hyprpm enable HyprWindowShade
hyprpm reload
```

Then add this line once near the end of `~/.config/hypr/hyprland.lua`:

```lua
require("hypr.omadecor")
```

Open **OD → Effects**, click **Check again**, choose an effect for each event,
and click **Apply**. An unknown Hyprland/HyprWindowShade fingerprint is safely
suspended until it is validated or you explicitly choose **Test anyway**.
OmaDecor only rewrites `~/.config/hypr/omadecor.lua`; it does not touch manual
HyprWindowShade rules.

Use **OD → Applications → FX setup** to make an event inherit the global
selection, disable it for that application, or select another compatible
effect. **Disable all FX** takes precedence over those event overrides.

## Local Development

```bash
git clone https://github.com/ZA512/OmaDecor.git
cd OmaDecor
./scripts/check.sh
hyprctl plugin load "$PWD/native/omadecor-native.so"
hyprctl plugin list
```

Use an absolute path with `hyprctl plugin load`; manual loading lasts only for
the current session. Never start another Quickshell process. After updating an
installed plugin copy, run `omarchy restart shell`.

Inspect runtime state with:

```bash
omarchy-shell omadecor status | jq
hyprctl configerrors
```

The stock Hyprland border is set to zero only while native Decorations are
active, preventing a double border. OmaDecor stores user intent in
`~/.config/omadecor/config.json`. Applying Effects atomically generates
`~/.config/hypr/omadecor.lua`.

## Decoration Theme Format

OmaDecor is migrating native decorations to inert declarative files named
`*.omadecor.json`. The V1 Core schema, semantic compiler, and canonical Raised
Edge example are available now:

```text
decorations/schema/decoration-theme-v1.schema.json
decorations/styles/raised-edge.omadecor.json
docs/decorationthemeformat.md
```

Validate a theme while authoring it with:

```bash
node scripts/validate-theme.js path/to/theme.omadecor.json
```

To use a custom theme, place it in the owned user directory and enter only its
filename in **OD → Decoration → User theme file**:

```bash
mkdir -p ~/.config/omadecor/themes
cp my-theme.omadecor.json ~/.config/omadecor/themes/
```

OmaDecor validates the theme in Quickshell and again in the native plugin. It
rejects symlinks, files over 256 KiB, unsupported capabilities, cyclic
references, and rendering-budget violations. Invalid themes fall back to the
built-in Raised Edge renderer without leaving windows undecorated.

## Disable or Remove

Disable Decorations before unloading the native plugin so the stock border is
restored cleanly:

```bash
omarchy-shell omadecor setModuleEnabled decorations false
hyprpm disable omadecor-native
hyprpm reload
omarchy plugin disable omadecor
```

See [docs/PRD.md](docs/PRD.md), [docs/DEVBOOK.md](docs/DEVBOOK.md),
[docs/TECHNICAL_SPIKE.md](docs/TECHNICAL_SPIKE.md), and
[docs/decorationthemeformat.md](docs/decorationthemeformat.md) for behavior,
architecture, theme authoring, and native-decoration evidence.

## Credits

Window effects are powered by
[HyprWindowShade](https://github.com/ManofJELLO/HyprWindowShade), created by
ManofJELLO and distributed separately under the MIT License. The bundled
starter shaders are original OmaDecor assets.

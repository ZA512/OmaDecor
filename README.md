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
  implemented. EffectPack V1 discovery, native Simple Dissolve, and the
  constrained Niri Circle Reveal open/close pack are available. An experimental
  GPL Incinerate pack is also included: open and close were checked on a
  large window, and close on floating windows. The external engine is
  installed only through an explicit, interactive confirmation.

## Install from GitHub

Install the Omarchy interface and the native Hyprland component separately:

### Prerequisites

This release targets Hyprland 0.56.x. [HyprWindowShade documents the same
requirement](https://github.com/ManofJELLO/HyprWindowShade#requirements).
Both native plugins are compiled locally, so install the build tools first on
Omarchy:

```bash
omarchy pkg add cmake cpio pkgconf git gcc make
```

On Arch, `pkgconf` provides `pkg-config`, while `gcc` provides both `gcc` and
`g++`. The Effects installer performs this check and, after confirmation,
offers the same Omarchy command for missing packages.

### Installation

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

Open **OD → Effects** and click **Install / update**. OmaDecor opens an
interactive terminal that explains and installs:

- HyprWindowShade through `hyprpm`;
- the separately maintained Hyprland-Shader pack under
  `~/.local/share/omadecor/shader-packs/`.

The equivalent repository command is:

```bash
bash scripts/install-effects.sh
```

The installer verifies Hyprland compatibility and the documented build
requirements (`cmake`, `cpio`, `pkg-config`, `git`, `g++`, `gcc`, and `make`)
before invoking `hyprpm`. If the cached Hyprland headers are stale, it runs
`hyprpm update` and retries. Every package installation and password prompt
remains visible in the interactive terminal.

HyprWindowShade asks `hyprpm reload -n` to run at session startup. OmaDecor's
enabled shell service performs that reload before restoring the saved Effects
configuration, so no additional Hyprland startup hook is required. After a
Hyprland upgrade, reopen **OD → Effects → Install / update** so `hyprpm` can
rebuild the plugin against the new headers. Do not bypass the version guard.

Upstream currently describes HyprWindowShade as not stress-tested and tested
only with AMD graphics on Arch. OmaDecor therefore treats a new compositor or
engine fingerprint as untested and keeps Effects suspended until explicitly
approved; Decorations and HUD remain available.

After installation, click **Check again**, then click an event to open the
effect picker. Search by name, project, author, or ID to narrow the choices;
**Clear** restores the full list. Choices are grouped as defaults, EffectPacks,
OmaDecor basics, and external shaders; packs that declare a high rendering
cost are labelled. The external pack contributes 55 open/close pairs such as
Fire, Smoke, Dissolve, Matrix, Plasma, and Voronoi Shatter. Click **Apply** after
choosing. An unknown Hyprland/HyprWindowShade fingerprint is safely suspended
until it is validated or you explicitly choose **Test anyway**. OmaDecor only
rewrites and evaluates `~/.config/hypr/omadecor.lua`; it does not touch the
main Hyprland configuration or manual HyprWindowShade rules. **None** removes
OmaDecor's previous shader tag from windows that are already open when you
click **Apply**. The main Effects On/Off switch applies immediately; individual
effect choices and application overrides still need **Apply**.

Each global event has its own timing slider. Open and Close default to 0.65 s
and 0.80 s so detailed shaders remain visible; Focus/Unfocus stay near 0.30 s
and Urgent defaults to 0.60 s. Transform events expose a shorter **Settle**
tail (0.25–0.45 s by default) because their main duration is controlled by
Hyprland's own animation. Application-specific effects inherit the timing of
their event.

The shader pack is not redistributed by OmaDecor and contains mixed upstream
attributions; its own `LICENSE` remains authoritative.

Use **OD → Applications → FX setup** to make an event inherit the global
selection, disable it for that application, or select another compatible
effect. **Disable all FX** takes precedence over those event overrides.

### Local EffectPack V1

OmaDecor ships `omadecor/simple-dissolve` as a self-contained open/close pack
and `liixini/circle` as a Niri-source compatibility example. Circle's source
is pinned and unchanged; OmaDecor compiles it into HWS-ready shaders in
`~/.cache/omadecor/effects/niri-v1/`. This requires `glslangValidator`
(`omarchy pkg add glslang`), and currently supports only Niri open/close
shaders using the documented common subset. Visual fidelity across GPUs and
monitor layouts is still being validated.

The three bundled packs include animated previews rendered offscreen from their
compiled shaders on a synthetic window. Regenerate them together with
`node scripts/render-shader-previews.js all`. Authoring requires Node,
ImageMagick, `g++`, EGL/GLES headers, and an EGL surfaceless OpenGL ES 3.2
renderer; installation does not. To generate previews for the separately
installed Hyprland-Shader collection, run
`node scripts/render-shader-previews.js external` (all 55 pairs) or
`node scripts/render-shader-previews.js external:fire` (one pair), then reopen
the Effects page or use **Check again**. Generated GIFs stay under
`~/.cache/omadecor/effects/previews/hyprland-shader/`; the original pack is
untouched. Each source hash changes the cache key, and reruns skip cached
previews. External shaders execute on the GPU only when this command is run;
use it only for a pack you trust. A process timeout cannot prevent every GPU
driver hang. No user window is recorded, and offscreen previews do not
guarantee identical compositor rendering.

`bmw/incinerate` is an **experimental** Burn My Windows port. Its GPL-3.0-or-later
shader and licence are confined to `effects/packs/bmw/incinerate/`; no BMW code
is copied into the OmaDecor core. The compiled effect shows fire,
smoke, and embers on full-size and 900×600 floating test windows. Other GPUs
and monitor layouts are not yet validated. Scale, turbulence, and fire color are
editable from **Effects → choose Incinerate → Details**. The pack's Subtle and
Dramatic presets are available there too. Click **Apply** after changing a
parameter or event duration: OmaDecor validates the values and compiles
separate open/close shaders in its user cache. Its preview uses default
parameters and does not remove the experimental label. Leave it unselected if
you need predictable behavior.
Additional local packs can be placed under a namespaced directory such as:

```text
~/.local/share/omadecor/effects/acme/my-effect/
├── effect.json
├── open.glsl
├── close.glsl
└── LICENSE
```

Click **Check again** to rescan. V1 packs contain metadata, single-pass GLSL,
optional preview assets, licence and credits only. Absolute paths, traversal,
symlinked files, executable helpers and shaders that fail validation are not
loaded. User-installed packs require `glslangValidator`; on Omarchy install it
with `omarchy pkg add glslang`. See `effects/schema/effect.schema.json` for the
manifest contract.

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

To use a custom theme, place it in the owned user directory:

```bash
mkdir -p ~/.config/omadecor/themes
cp my-theme.omadecor.json ~/.config/omadecor/themes/
```

Open **OD → Decoration** and select it with the theme arrows. The directory is
watched, so matching files appear without entering a path. OmaDecor generates
number, color, boolean, and enum controls from the theme's `parameters`
definitions; **Reset values** restores the theme defaults (or the current
Omarchy accent where the theme references it).

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
The optional Incinerate pack is derived from
[Burn My Windows](https://github.com/Schneegans/Burn-My-Windows) by Simon
Schneegans and remains GPL-3.0-or-later; see its bundled `LICENSE` and `CREDITS`.

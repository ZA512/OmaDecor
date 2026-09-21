# Repository Guidelines

## Project Structure & Module Organization

`docs/PRD.md` defines product behavior; approved architecture and spike evidence live in `docs/DEVBOOK.md` and `docs/TECHNICAL_SPIKE.md`. The compositor-native Raised Edge implementation is in `native/`. Quickshell entry points are `Panel.qml`, `Service.qml`, and `manifest.json`.

Keep persistent configuration, theme/diagnostic bridges, and normalized HUD state in `core/`; native style metadata and registries in `decorations/`; click-through HUD surfaces and system metrics in `hud/`; HyprWindowShade orchestration in `effects/`; compatibility fingerprints in `compatibility/`; settings pages in `ui/`; and automated checks in `tests/`. Decorations must not depend on Quickshell geometry tracking, and neither Decorations nor HUD may depend on Effects.

## Build, Test, and Development Commands

```bash
./scripts/check.sh
make -C native clean all
hyprctl plugin load "$PWD/native/omadecor-native.so"
hyprctl plugin list
```

`check.sh` validates the Omarchy manifest, lints QML, and builds the native plugin. Load only an absolute `.so` path built against the exact running Hyprland ABI. Never start a second Quickshell instance; use `omarchy restart shell` after installed QML changes.

Inspect runtime state with `omarchy-shell omadecor status`. Module toggles use `setModuleEnabled <decorations|hud|effects> <true|false>`.

## Coding Style & Naming Conventions

Use four-space indentation in QML/JavaScript and one component per file. Name QML components in `PascalCase`, properties/functions in `camelCase`, and stable IDs in kebab-case. C++ follows the existing Hyprland-style conventions and must compile cleanly with `-Wall -Wextra -Wpedantic`. Keep plugin configuration under `plugin:omadecor:*` and generated effect rules under `omadecor-effects-*`.

## Testing Guidelines

For native decorations, verify tiled/floating transitions, interactive move/resize, layout/workspace animations, focus colors, fullscreen, exclusions, open/close, multiple monitors, negative coordinates, and mixed scaling. The stock Hyprland border must be zero during visual tests. HUD tests separately verify click-through behavior and hide/settle/reappear timing. Name regression tests after behavior, such as `raised_edge_fullscreen_exclusion`.

## Commits, Pull Requests, and Safety

Use concise imperative commits, optionally Conventional Commit prefixes. PRs must reference a milestone, list validation and exact Hyprland ABI, and include visual evidence for rendering changes. Never use `sudo`, hooks, `curl | sh`, or destructive writes. Persist user intent only under `~/.config/omadecor/`; generate only `~/.config/hypr/omadecor.lua`, atomically and with symlink rejection; preserve user HyprWindowShade rules.

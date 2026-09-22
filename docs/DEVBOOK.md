# Devbook — OmaDecor

**Status:** M0–M6 implemented locally; HyprWindowShade and physical multi-monitor validation pending
**Last verified:** 2026-09-21  
**Product source of truth:** [`PRD.md`](PRD.md), as amended by this decision record

## 1. Approved Architecture

OmaDecor has three independent runtime modules:

```text
OmaDecor
├── Decorations — native Hyprland plugin (`native/`)
├── HUD — Quickshell service/panel/bar widget (`Service.qml`, `Panel.qml`, `BarWidget.qml`, `hud/`)
└── Effects — external HyprWindowShade integration (`effects/`)
```

Raised Edge is an `IHyprWindowDecoration`. Hyprland assigns its extents and invokes its draw method inside the compositor render pipeline. It does not use window geometry polling, layer-shell surfaces, or a Quickshell `PanelWindow`.

Quickshell remains appropriate for HUD content. `GeometryTracker` is now HUD-only: while the target geometry changes, the HUD hides, settles, repositions, and fades back in. Effects remain optional and delegated to HyprWindowShade.

`hud/HudHost.qml` creates one passive layer-shell host per output. Every host has an empty input region and no keyboard focus. Only the host matching the stable target monitor is visible. It renders application/title/workspace near the top-left and global CPU/RAM/network metrics near the bottom-right, folding cards inside the window bounds when no outside space exists.

`hud/SystemMetrics.qml` reads `/proc/stat`, `/proc/meminfo`, and `/proc/net/dev` every two seconds only while HUD is enabled. It launches no process and degrades each unavailable metric independently.

## 2. Verified Platform Baseline

| Component | Verified state |
| --- | --- |
| Omarchy | `4.0.4-1` |
| Quickshell | `0.3.1-1` |
| Hyprland | `0.56.2`, commit `efb5099…` |
| Hyprland ABI | `efb5099…_aq_0.15_hu_0.14_hg_0.5_hc_0.1_hlg_0.6` |
| Display tested | `DP-1`, `3440×1440`, scale `1` |
| Native plugin | Built and loaded successfully |

The plugin performs an exact Hyprland ABI check at load time. A rebuild is mandatory after any Hyprland or relevant Hypr library ABI change.

## 3. Native Decoration Contract

The MVP implements:

- top/right main color with `light_width`;
- bottom/left derived darker color with `dark_width`;
- active and inactive colors;
- fullscreen and `decorate = false` suppression;
- case-insensitive exact class exclusions;
- compositor-managed extents and damage.

Configuration keys live under `plugin:omadecor:*`. The stock Hyprland `general.border_size` must be `0` while Raised Edge is enabled to prevent a deliberate double border. See [`native/README.md`](../native/README.md).

The decoration is sticky to all four window edges, reserved like a normal border, rendered over the window, and marked as part of the main window. Workspace render offsets and floating offsets come directly from Hyprland during each render pass.

`decorations/NativeDecorationRegistry.qml` is the style-selection boundary. Raised Edge metadata and its settings schema live outside the renderer. The current renderer remains deliberately small; future native styles must register their metadata rather than adding QML positioning surfaces.

The declarative decoration format is being introduced behind that boundary.
`docs/decorationthemeformat.md` defines the target language;
`decorations/schema/decoration-theme-v1.schema.json` and
`decorations/ThemeCompiler.js` define the executable V1 Core contract. The
compiler currently accepts `edge`, `frame`, and `rect` primitives, solid paint,
focused variants, and OKLCH color derivation. It rejects unsupported
capabilities, cyclic references, invalid overrides, and finite-budget
violations. The canonical Raised Edge recipe is
`decorations/styles/raised-edge.omadecor.json`.

The compiler is connected to the native draw path. Quickshell validates the
selected file for immediate GUI feedback, while `native/ThemeEngine.cpp`
performs an independent bounded parse and compilation inside the plugin. The
renderer receives only compiled rectangle/edge operations and never interprets
JSON per frame. A rejected or missing theme falls back to the specialized
Raised Edge implementation.

User themes are selected by basename only and resolved under
`~/.config/omadecor/themes/`; native loading rejects symlinks, non-regular
files, files over 256 KiB, unsupported capabilities, cycles, and exceeded
budgets. The GUI watches this directory, exposes a basename-only catalogue,
and generates bounded controls for number, color, boolean, and enum
parameters. Overrides are stored separately in
`decorations.parameters`, validated in both runtimes, and sent to Hyprland as
a bounded scalar JSON object.

Theme mode is enabled by default. `core/ThemeBridge.qml` consumes Omarchy's existing `qs.Commons.Color` singleton, so a theme switch updates the native active color without file polling. Inactive windows use the same theme accent with configurable opacity; manual active/inactive colors remain available when theme mode is disabled.

## 4. Repository Boundaries

```text
native/                    Hyprland plugin and build
core/                      normalized state; HUD geometry only
hud/                       Quickshell HUD surfaces and metrics
effects/                   HyprWindowShade detection, catalogue, rules, and shaders
compatibility/             tested fingerprints
docs/                      decisions and evidence
tests/                     automated regression tests
```

`Service.qml` must never instantiate a Quickshell decoration host. The rejected QML implementation is documented in the spike rather than retained as runtime code.

## 5. Persistent Core State

`core/ConfigStore.qml` owns `~/.config/omadecor/config.json` with `schemaVersion: 1`. It validates and clamps native settings, coalesces writes, uses `FileView.atomicWrites`, and refuses to write through a symlink. Missing configuration creates safe defaults; malformed configuration reports a degraded state and retains the last valid in-memory state until the user repairs or explicitly resets it.

The three desired module toggles are independent. Decorations are enabled by default; HUD and Effects default off so installation never introduces an unsolicited overlay or GPU effect. Disabling Decorations restores the configured stock Hyprland border before suppressing Raised Edge. If the native plugin is unavailable, the bridge restores that stock border and leaves HUD/Effects state untouched.

`core/RuntimeDiagnostics.qml` performs bounded, explicit `/usr/bin/hyprctl` probes at startup and on refresh. It does not poll. `core/NativeBridge.qml` applies only normalized values through Hyprland's Lua configuration evaluator and exposes a module-local error state.

Application rules are normalized, deduplicated by case-insensitive class, and stored in `applications`. Decorations, HUD, and Effects exclusions are independent. Decoration exclusions are converted to exact native class matches; unsafe class strings never reach `hyprctl`. The panel lists running applications and retains the last active non-OmaDecor window for quick rule creation.

Effects keep desired state separate from runtime permission. `EngineDetector` distinguishes a loaded plugin from a hyprpm state entry; `CompatibilityManager` fingerprints the Hyprland ABI and the metadata actually exposed by HyprWindowShade. Unknown fingerprints are `UNTESTED` and safely suspended unless the user records an exact-fingerprint override. `EffectsManager` atomically owns only `~/.config/hypr/omadecor.lua`; generated rules are prefixed `omadecor-effects-*`, and manual rules are untouched. Application-specific tags override global fallback tags. `None` and whole-application exclusions use a transparent pass-through shader, with exclusion taking precedence over stored per-event choices.

## 6. Build and Development

```bash
./scripts/check.sh
hyprctl plugin load "$PWD/native/omadecor-native.so"
hyprctl plugin list
omarchy bar put omadecor --section right
```

`check.sh` validates the Omarchy manifest, lints QML, and builds the shared object. For release installation, prefer `hyprpm`; it rebuilds plugins against the running Hyprland version. Manual loading is development-only and requires an absolute path.

Do not launch a second Quickshell instance. After changing installed QML plugin files, use `omarchy restart shell`. After changing Lua configuration, run `hyprctl reload` and `hyprctl configerrors`.

## 7. Testing Gates

Native decoration acceptance covers tiled/floating transitions, interactive move/resize, layout and workspace animations, active/inactive changes, fullscreen, exclusions, open/close, monitor transfer, negative origins, and mixed scale. The local machine cannot close the multi-monitor gates.

HUD acceptance is separate: click-through surfaces, immediate hide on movement, stable repositioning, panel focus behavior, and no recurring external `hyprctl` process.

Effects acceptance is also separate and must pass when HyprWindowShade is absent, unloaded, incompatible, or broken.

M1 runtime validation covers first-run config creation, atomic persistence, all three toggles, native width/color/exclusion clamping, stock-border restoration, panel service identity, malformed JSON degradation, explicit reset, and a clean `hyprctl configerrors` result.

M2 local validation covers style registry discovery, theme-accent propagation (`#00e5ff` on the development theme), inactive alpha propagation, manual/theme color switching, structured application-rule persistence, native exclusion add/remove, running-application discovery, panel lifecycle, and monitor diagnostics. The available hardware reports one scale-1 monitor, so negative-origin, mixed-scale, and cross-monitor transfer remain blocked rather than inferred.

M3 local validation covers real HUD rendering, independent metrics, fullscreen suppression, per-application HUD exclusion and recovery, and click-through construction (`mask: Region {}`). During a scripted floating resize, the first geometry change was detected 23 ms after the command sequence began; hide occurred in the same sample, settling began 80 ms after the final change, stability was accepted after 128 ms, and the configured fade-in duration was 150 ms. Interactive mouse behavior and physical multi-monitor transfer remain manual gates.

## 8. Milestones

1. **M0 — Native spike:** accepted locally; multi-monitor validation remains an M2 gate.
2. **M1 — Plugin core:** implemented, including the settings bar widget; persistent loading through `hyprpm` remains a release-packaging task.
3. **M2 — Decorations:** functional implementation complete locally; the physical multi-monitor matrix remains an acceptance gate.
4. **M3 — HUD:** implemented and locally validated; mouse/multi-monitor acceptance remains pending.
5. **M4 — Effects integration:** implemented locally; passive detection, exact-fingerprint suspension, override, GUI status, and installation guidance are functional.
6. **M5 — Effects configuration:** implemented locally for the bundled shader catalogue, global event mapping, per-application inheritance/exclusion/replacement, owned-rule generation, and explicit Apply workflow.
7. **M6 — Compatibility:** fingerprint lifecycle, exact-fingerprint overrides, effect-specific degradation, safe suppression, transition notifications, and diagnostics are implemented. No HyprWindowShade combination is marked validated until the external engine is installed and the effect matrix is tested.
8. **M6.1 — Decoration themes:** V1 Core schema, dual semantic validation, native compilation/rendering, safe fallback, watched user-theme catalogue, generated parameter controls, canonical Raised Edge theme, and regression tests are implemented.
9. **M7 — Release:** `hyprpm` commit pins, documentation, licenses, recovery, and exact release validation.

## 9. Risks and Maintenance

| Risk | Mitigation |
| --- | --- |
| Hyprland plugin ABI/API churn | Exact hash guard, `hyprpm` rebuilds, pin/test each supported release |
| Plugin crash affects compositor | Small hook-free implementation; fail at load on mismatch |
| Duplicate stock border | Config validation and explicit `border_size = 0` guidance |
| Native/QML state divergence | Decoration configuration belongs to the native module; HUD consumes its own state |
| Multi-monitor regressions | Block M2 acceptance until mixed-scale and negative-origin hardware tests pass |

## References

- [Hyprland plugin guidelines](https://wiki.hypr.land/Plugins/Development/Plugin-Guidelines/)
- [Hyprland plugin usage](https://wiki.hypr.land/Plugins/Using-Plugins/)
- [Hyprland `IHyprWindowDecoration` (v0.56.2)](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/render/decorations/IHyprWindowDecoration.hpp)
- [Official borders-plus-plus plugin](https://github.com/hyprwm/hyprland-plugins/tree/main/borders-plus-plus)

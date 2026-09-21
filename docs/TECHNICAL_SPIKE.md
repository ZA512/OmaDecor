# Technical Spike — Native Raised Edge

**Status:** native prototype accepted on the single-monitor development system  
**Decision:** architecture B — native decoration + Quickshell HUD + HyprWindowShade effects  
**Decision date:** 2026-09-20

## Question and Outcome

The original spike asked whether a Quickshell layer-shell frame could follow a Hyprland window without visible drift. It cannot meet that requirement. OmaDecor now renders Raised Edge as a native Hyprland window decoration.

| Module | Owner |
| --- | --- |
| Raised Edge | Hyprland plugin render/decorations pipeline |
| HUD | Quickshell; hide while moving, settle, then show |
| Effects | HyprWindowShade |

## Rejected Quickshell Decoration

The old implementation created four `PanelWindow` edge surfaces from `DecorationHost.qml`. `GeometryTracker` refreshed compositor objects at 16 Hz when stable and 30 Hz while unstable. It faded the frame for 80 ms and required 120 ms of stable geometry before showing it again.

The visible failure is architectural: Hyprland moves the real window immediately, while a separate Wayland client learns the new coordinates later and commits four independent layer surfaces. A 16 Hz sentinel has a theoretical detection delay of 0–62.5 ms before IPC, QML, layer-shell, and frame scheduling costs. The 80 ms fade also intentionally leaves the stale frame visible. Increasing polling frequency would reduce but not remove this race.

Measured programmatic changes returned to `STABLE` after 129–132 ms. Individual first-difference observations varied from 9–56 ms, but spontaneous native-object updates made those samples unsuitable for selecting a polling frequency. The user-observed interactive lag is therefore the decisive NO-GO evidence.

## Native API Findings

Hyprland 0.56.2 exposes `IHyprWindowDecoration`, `HyprlandAPI::addWindowDecoration`, compositor positioning replies, decoration extents, layers/flags, and render-pass elements. OmaDecor uses these public plugin mechanisms without function hooks.

Synchronization no longer has a user-space timing chain:

```text
window state/layout animation
        → Hyprland decoration positioning
        → OmaDecor draw callback in the same compositor frame
```

There is no geometry detection, overlay hide, stabilization delay, or re-show step for Raised Edge. Interactive move/resize, layout animations, workspace animations, and float/tile transitions all use Hyprland’s current assigned decoration geometry and render offsets.

## Implemented Prototype

`native/` builds `omadecor-native.so` for the exact running ABI. The decoration:

- reserves asymmetric extents: dark left/bottom, light top/right;
- derives the dark RGB value using `shade_factor`;
- switches colors with compositor focus state;
- suppresses itself in fullscreen, for `decorate = false`, and for excluded classes;
- attaches to existing mapped windows and future `window.open` events;
- refreshes positioning only for configuration, class, fullscreen, and floating changes;
- rejects an exact ABI mismatch before activation.

The repository `Service.qml` no longer instantiates the Quickshell decoration host. Runtime diagnostics report `decorationBackend: "hyprland-native"` and `surfaces: []`. HUD tracking is disabled by default until a HUD surface consumes it, so the 16 Hz sentinel does not run continuously.

## Verification Evidence

Tested on Hyprland `0.56.2` (`efb5099…`) with one `3440×1440`, scale-1 monitor:

| Scenario | Result | Evidence |
| --- | --- | --- |
| Build and exported entry points | PASS | Clean `-Wall -Wextra -Wpedantic` build; all three plugin exports present |
| Exact ABI load | PASS | `hyprctl plugin list` reports `omadecor-native` 0.1.0 |
| Stock border disabled | PASS | `general:border_size = 0`; only Raised Edge visible |
| Active/inactive colors | PASS | Top pixel changed `(70,212,251)` → `(97,112,134)`; dark edge changed too |
| Class exclusion | PASS | `excluded_classes = "foot"` removed all four sampled edge pixels |
| Fullscreen exclusion | PASS | All four display-edge samples contained only window content |
| Float/tile transition | PASS | Decoration remained attached and plugin stayed loaded |
| Animated move/resize | PASS | Eight rapid position/size changes over 2.0 s; each captured frame had attached edges |
| Quickshell duplicate removed | PASS | Shell restart reports `surfaces: []` |
| Interactive mouse move/resize | PASS | User manually confirmed that the native result remains attached and acceptable |
| Workspace animation | PASS | Test window moved 2 → 3 → 2 through animated workspace changes; edges stayed attached |
| Multi-monitor/mixed scale | BLOCKED | One local monitor |

Temporary screenshots were inspected locally and deleted because they contained user window content.

## Maintenance Assessment

The result is visually correct by construction but has higher release maintenance than QML. Hyprland plugins are ABI-sensitive and C++ decoration APIs can change between releases. Each supported Hyprland update requires a rebuild plus compile/load and compositor matrix tests. `hyprpm` and exact commit pins reduce deployment risk; the hash guard prevents knowingly loading an incompatible binary.

The implementation deliberately avoids renderer function hooks and private symbol interception. This narrows the likely porting surface to decoration positioning, render-pass types, and event names.

## Decision

Choose **B**.

- **A is rejected** for window decoration because visible drift is inherent to an external overlay chasing compositor geometry.
- **B satisfies the invariant** that Raised Edge is always attached to the window, while preserving Quickshell for information-rich HUD surfaces and HyprWindowShade for effects.
- No third architecture is currently simpler without losing configurability or reimplementing compositor functionality.

Do not recreate a Quickshell decoration host. Complete the pending manual and multi-monitor rows before declaring Milestone 0 fully closed.

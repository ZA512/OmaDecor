# Effects Platform — Research Spike E0

Status: **architecture approved; E1–E3 implemented, E4 Incinerate experimental**  
Research date: 2026-09-22  
Approval date: 2026-09-23

## Decision summary

Keep **HyprWindowShade (HWS)** as the first execution backend, but stop exposing its tags outside a dedicated backend adapter. Introduce a normalized EffectPack contract and compile source formats into self-contained GLSL ES 3.20 artifacts before HWS sees them.

- **Niri open/close compatibility: GO**, limited initially to single-pass shaders using the common four-symbol subset.
- **Niri resize compatibility: NO-GO for V1** because it needs previous and next textures and geometry transforms HWS does not expose.
- **BMW compatibility: experimental for a selected Incinerate port**. A generic “all BMW effects” promise is a NO-GO without broader adapter evidence.
- **Hyprland PR #13900 backend: WATCH**, not an MVP dependency. It is still a draft and its contract is incomplete for OmaDecor.

This preserves the intended boundary:

```text
EffectPack -> Validator -> Source adapter -> Normalized artifact
                                                |
                                      IEffectsBackend
                                                |
                                   HyprWindowShadeBackend
```

## Evidence inspected

The conclusions below come from source inspection, not names or screenshots.

| Project | Revision inspected | Relevant evidence |
| --- | --- | --- |
| HyprWindowShade | [`4414596`](https://github.com/ManofJELLO/HyprWindowShade/tree/4414596c2fbb64cb5bb4aa7342900051338fed7a) | `README.md`, `ShaderEngine.cpp`, `Hooks.cpp`, `Globals.hpp` |
| Niri | [`5f4469b`](https://github.com/YaLTeR/niri/tree/5f4469b6a992492cf7221b269e9379f42e737649) | animation wiki sources, open/close/resize preludes and render elements |
| Niri -> KWin port | [`5dc70f1`](https://github.com/mj0x0/kwin-niri-shaders-port/tree/5dc70f19b993b35ecd60ce0c6a8f7f31f6173502) | `build/generate.py` compatibility shim and generated effects |
| Burn My Windows | [`9af4eb1`](https://github.com/Schneegans/Burn-My-Windows/tree/9af4eb1f27244985e9e4fb3e7e4067a4dd6598e4) | Incinerate shader, KWin setup/config glue, common shader contract |
| hyprfx | [`e3d093a`](https://github.com/xhos/hyprfx/tree/e3d093ac6d0711f6ee9a58d6dc013a3a507970d8) | snapshot/render-pass implementation and four BMW-derived shaders |
| PlasmaZones | [`b442881`](https://github.com/fuddlesworth/PlasmaZones/tree/b442881cccfd3d68e16e3b3e515a82d5f9961944) | pack registry/schema, BMW shim, Incinerate port, animation contract |
| Hyprland PR #13900 | [`0501c9b`](https://github.com/hyprwm/Hyprland/pull/13900/commits/0501c9ba6ea6ac985f5597a2f32427bfa6f4d284) | draft shader animation implementation and PR limitations |

## API comparison matrix

| Feature | HWS | Niri | BMW / KWin | Hyprland PR #13900 |
| --- | --- | --- | --- | --- |
| Window texture | `sampler2D tex` | `niri_tex`, plus geometry-to-texture matrix | KWin `sampler`; BMW helper `getInputColor()` | function argument `sampler2D tex` |
| Shader output | `fragColor` | `open_color()` / `close_color()` return premultiplied `vec4` | BMW body calls `setOutputColor()`; KWin port writes fragment color | returns `vec4[2]`: color, sample UV and alpha |
| Progress | linear `progress`, 0 -> 1 | raw `niri_progress` plus clamped/eased `niri_clamped_progress` | linear `uProgress`; duration/curve owned by KWin glue | animation-curve progress; close is reversed before the function call |
| Random seed | stable scalar `seed` | stable scalar `niri_random_seed` | usually `uSeed` as `vec2`, initialized per animation | stable scalar `randomSeed` |
| Window size | `surface_size`; close also needs `window_rect` because its texture is monitor-sized | `niri_geo_size` and `size_geo` | `uSize` / texture dimensions | function argument `size` |
| Coordinates | `v_texcoord`; close window sub-rect is in `window_rect` | geometry coordinates transformed by `niri_geo_to_tex` | BMW normalized `iTexCoord`; KWin needs a Y-axis bridge | normalized `coords` from Hyprland surface shader |
| Alpha model | compositor surface is premultiplied; wrapper clamps RGB to alpha | premultiplied | BMW computes in straight alpha, then premultiplies in its output bridge | compositor-native surface path |
| Open | yes, one-shot tag | yes | yes in official KWin port | yes |
| Close | yes, held Hyprland snapshot | yes | yes in official KWin port | yes, currently coupled to snapshot/fade behavior |
| Motion | move, resize, workspace and state events; one current texture | custom resize has previous + next textures; movement itself has no custom shader contract | not part of the BMW open/close contract | no; open/close only |
| Custom parameters | no arbitrary uniform binding; only HWS fixed uniforms | no generic parameter metadata | KWin glue binds effect-specific uniforms | none in the draft contract |
| Failure behavior | failed stage is skipped and retried after file mtime changes | retains the previous successfully compiled shader | KWin effect owns compilation/setup | PR notes invalid code can make the animated window transparent |

### HWS execution notes

HWS is the broadest event backend available to OmaDecor today. It exposes open, close, move, resize, workspace, focus, urgent, floating, tiled and fullscreen tags, along with motion uniforms. One-shot duration precedence is rule `@seconds`, shader `// @duration`, then 0.3 seconds, capped at 5 seconds.

The close path is materially different from open: it shades a monitor-sized Hyprland fadeout snapshot. A compatibility adapter must remap `v_texcoord` through `window_rect`; treating the entire snapshot as the window will distort coordinates and may shade unrelated pixels. A close effect must reach zero alpha at progress 1 unless it explicitly uses HWS overlay mode.

HWS cannot currently populate pack-specific uniforms such as `flameSize` or `uColor`. V1 should therefore materialize validated parameter values as finite GLSL constants in a generated artifact. This keeps HWS replaceable and avoids adding BMW knowledge to the plugin.

### Niri contract notes

Niri prepends a documented shader prelude and expects `open_color(vec3, vec3)` or `close_color(vec3, vec3)`. The widely reused open/close subset is:

```text
niri_clamped_progress
niri_random_seed
niri_tex
niri_geo_to_tex
```

The KWin port demonstrates that many shaders can remain unchanged behind a small shim, with a coordinate flip and progress mapping. However, Niri explicitly gives this custom shader interface no backwards-compatibility guarantee. Effects using raw spring progress, Niri-only geometry matrices, or resize’s two textures must be rejected or marked degraded rather than silently approximated.

### BMW contract notes

BMW is a framework, not only a fragment file. Incinerate depends on common helpers plus:

```text
uProgress, uForOpening, uDuration, uSize
uSeed (vec2), uStartPos (vec2)
uColor, uScale, uTurbulence
```

The official KWin glue chooses a random/pointer start position, binds parameters, and defaults to a 2000 ms duration. PlasmaZones confirms that a reusable BMW shim is viable, but also shows real adaptations: premultiplied/straight-alpha conversion, parameter-slot mapping, elapsed-time substitution and coordinate handling. hyprfx proves compositor-native snapshot rendering can run BMW-derived shaders under Hyprland, but it is a GPL plugin with compile-time effect selection and close-only behavior; it is evidence, not the target architecture.

## License and provenance matrix

| Material | License observed | OmaDecor handling |
| --- | --- | --- |
| HyprWindowShade | MIT | External backend; retain author/project attribution. |
| Niri compositor code/docs | GPL-3.0 | Research reference only; do not copy implementation into MIT code. |
| `kwin-niri-shaders-port` shim/generated packages | MIT | May inform or seed a compatible adapter with notices retained. |
| Individual Niri community shaders | Per-source; verify every effect | Pack manifest must record exact upstream URL, revision, authors and SPDX identifier. |
| Burn My Windows Incinerate/common helpers | GPL-3.0-or-later | Keep in a clearly GPL pack; retain copyright and source notices. |
| hyprfx | GPL-3.0 | Research/reference unless GPL code is intentionally isolated in a GPL pack/plugin. |
| PlasmaZones application | GPL-3.0 | Architecture reference only. |
| PlasmaZones animation library/original shaders | LGPL-2.1-or-later; BMW-derived files remain GPL-3.0-or-later | Verify at file level; never infer one license for the entire tree. |
| Hyprland / PR #13900 | BSD-3-Clause | Future backend reference; attribution required if code is incorporated. |

The pack, not the OmaDecor core repository, is the distribution boundary for copyleft shader content. `LICENSE` and `CREDITS` are mandatory for every non-native pack, and the GUI must expose provenance.

## Proposed EffectPack V1

One directory contains one effect. V1 is inert: JSON, GLSL, preview assets, license and credits only. No executable scripts or network access are allowed.

```json
{
  "schemaVersion": 1,
  "id": "bmw/incinerate",
  "name": "Incinerate",
  "version": "1.0.0",
  "description": "Heat-driven dissolve with embers.",
  "source": {
    "type": "ported",
    "format": "bmw",
    "project": "Burn My Windows",
    "url": "https://github.com/Schneegans/Burn-My-Windows",
    "revision": "<immutable revision>",
    "authors": ["Simon Schneegans"],
    "portAuthors": ["<porter>"],
    "license": "GPL-3.0-or-later",
    "adaptationNotes": "BMW compatibility shim for HWS."
  },
  "events": ["open", "close"],
  "shaders": {"open": "open.glsl", "close": "close.glsl"},
  "requires": [
    "shader.progress",
    "shader.random-seed",
    "shader.window-texture",
    "shader.window-size"
  ],
  "duration": {"defaultMs": 1200, "minMs": 200, "maxMs": 3000},
  "renderingCost": "high",
  "parameters": [
    {"id": "scale", "name": "Scale", "type": "float", "default": 1.0,
     "min": 0.1, "max": 3.0, "step": 0.1},
    {"id": "color", "name": "Fire Color", "type": "color",
     "default": "#ffb47f"}
  ],
  "presets": {
    "subtle": {"scale": 0.7},
    "dramatic": {"scale": 1.6}
  },
  "preview": "preview.webp"
}
```

Validation rules proposed for E2:

- IDs use `namespace/name`; versions use semantic versioning; event names use OmaDecor’s normalized kebab-case vocabulary.
- `additionalProperties: false` at security-sensitive levels; parameter and preset limits are bounded.
- All referenced files resolve inside the pack after canonicalization; reject absolute paths, `..`, symlinks escaping the pack, devices and FIFOs.
- Require a regular `LICENSE` file and complete provenance for `ported`, `adapted` and `external` sources.
- Parameter values must be finite and type/range checked before generating GLSL constants.
- V1 accepts one fragment shader per event, approved local includes and no custom vertex or multipass stages.
- Capability mismatch produces `INCOMPATIBLE`; compilation failure produces `BROKEN` for that effect/event only.

## Proposed `IEffectsBackend`

The interface should consume normalized artifacts, never source-format packs:

```text
id() -> string
probe() -> BackendStatus
capabilities() -> CapabilitySet
validate(artifact, event) -> ValidationResult
apply(configuration, artifacts) -> ApplyResult
deactivate() -> ApplyResult
diagnostics() -> BackendDiagnostics
```

`configuration` contains global event selections, durations, generated parameter values, exclusions and per-application overrides. `artifact` contains only backend-ready shader paths and normalized metadata. It does not contain `shader_close` or any other HWS tag.

`HyprWindowShadeBackend` alone owns:

- normalized-event -> HWS-tag mapping;
- rule names and Lua generation;
- duration encoding (`@seconds`);
- passthrough rules for exclusions;
- ABI detection, load state and compatibility fingerprint;
- atomic config write, reload and diagnostics.

E1 moved the rule generator to `effects/backends/HyprWindowShadeRuleGenerator.js`. Existing effect IDs and persisted selections remain unchanged, so the boundary migration does not discard user configuration.

## Niri compatibility feasibility

**GO scope:** open/close, single-pass, common four-symbol subset, premultiplied output, no off-window rendering. The adapter supplies local window coordinates, size, texture transform, clamped progress and seed. It should preserve the upstream function body whenever possible and record any transformation.

**Unsupported in V1:** custom resize, raw spring semantics, previous/next textures, source-specific external textures, arbitrary Niri compositor internals. Static analysis must detect these symbols and mark the event incompatible.

E3 succeeds only if one visually useful source shader works with an untouched or minimally transformed body on open and close. Otherwise the generic adapter becomes NO-GO and individual ports remain possible.

## BMW compatibility and Incinerate strategy

**Conditional GO:** build a GPL compatibility pack, not BMW assumptions in OmaDecor core.

Incinerate spike plan:

1. Pin one upstream BMW revision and copy only the required shader/helper material with SPDX headers, `LICENSE` and `CREDITS`.
2. Build one self-contained HWS open artifact and one close artifact from the same effect body.
3. Map HWS `progress`, `seed`, `surface_size`, `tex` and `v_texcoord` to the BMW contract. Derive a stable second seed component from HWS’s scalar seed.
4. Remap the HWS close snapshot through `window_rect` so Incinerate operates in window-local UV space.
5. Convert texture samples from premultiplied to straight alpha for BMW helpers, then premultiply the final output.
6. Materialize validated color/scale/turbulence/start-position values as constants. Use deterministic/random start position first; pointer-relative close origin is deferred until the backend can provide reliable window-local pointer coordinates on every monitor.
7. Use the configured duration both for HWS `@seconds` and BMW elapsed-time math. Start visual comparison near BMW’s 2000 ms reference, then tune presets rather than changing upstream equations blindly.
8. Test varied aspect ratios, mixed scale, tiled/floating windows, multiple monitors, negative coordinates, open/close interruption and repeated rapid closes.

GO requires a side-by-side recording judged comparable to BMW, clean alpha at the last close frame, no unrelated snapshot pixels, and no compositor instability. If most subsequent BMW effects need effect-specific runtime machinery, retain Incinerate as an individual GPL port and mark a generic BMW layer NO-GO.

## Hyprland native backend assessment

PR #13900 is promising because it executes in Hyprland’s surface shader and accepts texture, coordinates, size, progress and seed. However, as inspected it is still a draft, supports only open/close, has no metadata/parameter channel, reports transparent animated windows on invalid shader code, and notes unresolved coupling to close snapshots/fade plus decoration behavior. It must not replace HWS in the MVP.

The backend boundary should nevertheless allow a future `HyprlandNativeBackend` to consume the same normalized packs when a stable API lands. Capability negotiation, rather than version-name guesses, decides which events it can run.

## Principal risks

| Risk | Mitigation / gate |
| --- | --- |
| Untrusted GLSL can hang or crash a GPU/compositor | No automatic downloads; explicit local install; bounded source/assets; compile validation; retain last known-good artifact. Absolute safety is not possible for arbitrary GLSL. |
| HWS ABI follows Hyprland internals | Keep exact fingerprint gating and isolate all HWS syntax in one backend. |
| Close snapshot coordinates differ from live-window coordinates | Mandatory `window_rect` adapter tests, including negative-origin monitors and rotation. |
| Parameter injection changes shader source | Typed constant generation, finite values, canonical formatting and content-addressed artifacts. Never splice raw user strings. |
| Niri interface changes | Record source revision and compatibility-layer version; reject unknown required symbols. |
| GPL content contaminates provenance or distribution expectations | Separate GPL pack, file-level SPDX, mandatory license/credits, no relicensing. |
| HWS has no arbitrary uniform API | Generate backend-ready shader variants in cache for V1; reconsider a parameter API only after the spikes. |
| Compiled effect looks correct only on one GPU | Validate AMD/Intel where available; record GPU/driver in compatibility evidence; mark untested combinations honestly. |
| Effect/decor/HUD conflict | Hide HUD during transient effects; test decoration visibility separately before defining `keep`/`hide`. |

## E0 conclusion and next review gate

E0 supports the target architecture: **normalized EffectPack + source adapters + replaceable execution backend**. No evidence supports importing a large shader collection now.

E1 and E2 are implemented: HWS knowledge is isolated behind the backend, and EffectPack V1 has an executable schema, validator, local registry, normalized metadata, capability filtering, and a native Simple Dissolve pack. The E2 core remains single-pass and self-contained.

## E3 implementation and evidence

The E3 adapter accepts only Niri `open_color` / `close_color` shaders using `niri_clamped_progress`, `niri_random_seed`, `niri_tex`, and `niri_geo_to_tex`. It maps HWS progress and seed directly, converts HWS texture coordinates to window-local geometry, and maps close's monitor snapshot through `window_rect`. It rejects unsupported Niri uniforms/symbols, directives, stages, and events. The original shader body is not rewritten. `glslangValidator` checks the generated GLSL, and content-addressed output is atomically stored in the user cache. A failed compile leaves any previous artifact intact.

The test pack is [`liixini/circle` at `238e7c7`](https://github.com/liixini/shaders/tree/238e7c70e317bb0ca0b0366cf0851b8de3ddc969/circle), MIT with original credits. Its open and close sources are byte-identical to that revision. Both artifacts compile and pass scanner/registry tests. The first live attempt was invalid as visual evidence: `ConfigStore.normalizedEffectId()` rejected `/` in pack IDs and silently replaced selections with `none`. After fixing that contract and adding a regression test, the generated HWS rule referenced the Niri artifact and a 2-second open capture visibly showed the circular reveal. A later 2-second close capture of an opaque GTK window clearly showed the shrinking circular mask. Foot close captures were not suitable evidence: the window content vanished immediately even with HWS Simple Fade, whereas Simple Fade and Circle both visibly animated the GTK window. Therefore **both Circle events are visually confirmed on the local machine; portability remains an acceptance gate**. The local test used one AMD display at scale 1; mixed scaling, negative monitor origins, other GPUs, and rapid interruption remain untested. Niri's unstable source API and unsupported resize/two-texture shaders remain explicit limitations.

## E4 implementation and evidence

The experimental [`bmw/incinerate`](https://github.com/Schneegans/Burn-My-Windows/tree/9af4eb1f27244985e9e4fb3e7e4067a4dd6598e4) pack contains byte-identical Incinerate and common GLSL from BMW revision `9af4eb1`, with GPL-3.0-or-later text, source notices, and credits. The compiler accepts only those pinned source hashes, validates numeric/color inputs, extracts the common helper section, and renames/removes the original `main`/custom-uniform declarations in the generated artifact. The source files remain untouched. Its HWS wrapper supplies progress, a stable two-component seed and edge origin, window-local size/UV, and straight-alpha BMW helpers around HWS's premultiplied texture. The close texture is remapped using `window_rect`. Generated GLSL passes `glslangValidator`; scanner/registry tests reject altered source and invalid parameters.

On Hyprland 0.56.2 with one 3440×1440 scale-1 AMD output, a temporary 2-second full-size test rendered a moving flame front, smoke, and embers on open and close, ending with a clean background; no compositor failure or `configerrors` was observed. A 900×600 floating close likewise showed the burn front, smoke, and embers after confirming that OmaDecor's pending configuration had been explicitly applied and the window carried the `shader_close` tag. A separate GTK close capture showed the window content burning away behind that front. The closes were dispatched through Hyprland; earlier tests that omitted Apply or killed the client process abruptly produced invalid captures, not evidence of a floating-window shader defect. No side-by-side BMW reference recording, mixed-scale/other-GPU test, or interruption matrix has been completed. The E5 implementation persists validated pack parameters and recompiles separate content-addressed artifacts with the selected open/close durations on Apply; tests confirm scale, turbulence, fire color, duration, and invalid-value rejection. **E4 is not GO; Incinerate remains explicitly experimental and the generic BMW adapter remains NO-GO.**

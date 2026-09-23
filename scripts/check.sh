#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
qmllint_bin=${QMLLINT_BIN:-/usr/lib/qt6/bin/qmllint}

cd "$repo_dir"
omarchy plugin validate .
"$qmllint_bin" -I /usr/lib/qt6/qml -I /usr/share/omarchy/shell \
  Service.qml \
  core/ConfigStore.qml \
  core/RuntimeDiagnostics.qml \
  core/NativeBridge.qml \
  core/HyprlandState.qml \
  core/GeometryTracker.qml \
  decorations/ThemeCompiler.js \
  decorations/DecorationThemeLoader.qml \
  effects/EngineDetector.qml \
  effects/EffectValidator.js \
  effects/EffectSearch.js \
  effects/EffectMetadata.js \
  effects/EffectPack.js \
  effects/EffectPackRegistry.qml \
  effects/ShaderCatalog.qml \
  effects/CompatibilityManager.qml \
  effects/EffectsManager.qml \
  effects/backends/HyprWindowShadeBackend.qml \
  hud/SystemMetrics.qml \
  decorations/NativeDecorationRegistry.qml

# `qs.*` is a Quickshell resource-root import resolved by the Omarchy host,
# not a filesystem QML module. Disable only the resulting static false positives.
"$qmllint_bin" -I /usr/lib/qt6/qml -I /usr/share/omarchy/shell \
  --import disable --unqualified disable --uncreatable-type disable --unresolved-type disable \
  BarWidget.qml \
  Panel.qml \
  core/ThemeBridge.qml \
  hud/HudHost.qml

jq -e '
  .schemaVersion == 1
  and .kind == "omadecor-decoration"
  and .id == "omadecor/raised-edge"
  and (.requires | index("primitive.frame")) != null
  and .parameters.inactiveOpacity.default == 0.55
  and (.layers | length) == 1
' decorations/styles/raised-edge.omadecor.json >/dev/null

jq -e '
  .["$schema"] == "https://json-schema.org/draft/2020-12/schema"
  and .properties.schemaVersion.const == 1
  and .properties.kind.const == "omadecor-decoration"
' decorations/schema/decoration-theme-v1.schema.json >/dev/null

jq -e '.schemaVersion == 1 and (.validated | type == "array") and (.effects | type == "array")' \
  compatibility/hyprwindowshade.json >/dev/null

bash -n scripts/install-effects.sh
bash -n scripts/scan-effect-packs.sh
bash -n scripts/scan-external-shaders.sh
bash -n scripts/compile-niri-shader.sh
bash -n scripts/compile-bmw-incinerate.sh

jq -e '
  .["$schema"] == "https://json-schema.org/draft/2020-12/schema"
  and .properties.schemaVersion.const == 1
  and .properties.kind.const == "omadecor-effect-pack"
' effects/schema/effect.schema.json >/dev/null

jq -e '
  .schemaVersion == 1
  and .kind == "omadecor-effect-pack"
  and .id == "omadecor/simple-dissolve"
  and .compatibility.events == ["open", "close"]
  and (.shaders | keys | sort) == ["close", "open"]
' effects/packs/native/simple-dissolve/effect.json >/dev/null

scripts/scan-effect-packs.sh --trusted-root effects/packs \
  | jq -se '
    length == 3
    and all(.[]; .ok)
    and ([.[].manifest.id] | sort) == ["bmw/incinerate", "liixini/circle", "omadecor/simple-dissolve"]
    and (.[] | select(.manifest.id == "liixini/circle") | .artifacts
        | has("open") and has("close"))
    and (.[] | select(.manifest.id == "bmw/incinerate") | .artifacts
        | has("open") and has("close"))
  ' >/dev/null

if command -v node >/dev/null 2>&1; then
  node scripts/validate-theme.js decorations/styles/raised-edge.omadecor.json
  node scripts/validate-theme.js tests/fixtures/edge-rect.omadecor.json
  node tests/decoration_theme_compiler.test.js
  node tests/effect_pack.test.js
  node tests/shader_preview.test.js
  node tests/effect_search.test.js
  node tests/config_effect_ids.test.js
  node tests/effects_rule_generator.test.js
fi

if pkg-config --exists egl glesv2; then
  ${CXX:-g++} -std=c++20 -Wall -Wextra -Wpedantic -fsyntax-only \
    scripts/preview-renderer.cpp $(pkg-config --cflags egl glesv2)
fi

native_test_dir=$(mktemp -d)
trap 'rm -rf -- "$native_test_dir"' EXIT
${CXX:-g++} -std=c++2b -Wall -Wextra -Wpedantic \
  -I native tests/native_theme_engine.test.cpp native/ThemeEngine.cpp \
  -o "$native_test_dir/theme-engine-test" $(pkg-config --cflags --libs json-c)
"$native_test_dir/theme-engine-test" \
  decorations/styles/raised-edge.omadecor.json \
  tests/fixtures/edge-rect.omadecor.json

if command -v glslangValidator >/dev/null 2>&1; then
  for shader in effects/shaders/*.glsl effects/packs/native/*/*.glsl; do
    glslangValidator -S frag "$shader"
  done
fi

make -C native all

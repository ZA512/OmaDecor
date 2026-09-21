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
  effects/EngineDetector.qml \
  effects/ShaderCatalog.qml \
  effects/CompatibilityManager.qml \
  effects/EffectsManager.qml \
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
  and .id == "raised-edge"
  and .renderer == "native:omadecor-native"
  and .settings.useThemeAccent.default == true
  and .settings.inactiveOpacity.default == 0.55
' decorations/styles/RaisedEdge.json >/dev/null

jq -e '.schemaVersion == 1 and (.validated | type == "array") and (.effects | type == "array")' \
  compatibility/hyprwindowshade.json >/dev/null

if command -v node >/dev/null 2>&1; then
  node tests/effects_rule_generator.test.js
fi

if command -v glslangValidator >/dev/null 2>&1; then
  for shader in effects/shaders/*.glsl; do
    glslangValidator -S frag "$shader"
  done
fi

make -C native all

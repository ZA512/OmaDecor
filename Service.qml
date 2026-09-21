import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "core"
import "decorations"
import "effects"
import "hud"

Scope {
    id: root

    property var shell: null
    property var manifest: null

    property bool debugEnabled: false
    property int panelOpenCount: 0
    property int panelCloseCount: 0
    property bool panelServiceIdentityMatched: false
    property string lastPanelPayload: ""

    readonly property bool configLoaded: configStore.loaded
    readonly property bool configHealthy: configStore.healthy
    readonly property string configError: configStore.lastError
    readonly property bool decorationsEnabled: configStore.decorationsEnabled
    readonly property bool hudEnabled: configStore.hudEnabled
    readonly property bool effectsEnabled: configStore.effectsEnabled
    readonly property var effectsEvents: configStore.effectsEvents
    readonly property string effectsCompatibilityStatus: effectsManager.status
    readonly property bool effectsAllowed: effectsManager.allowed
    readonly property bool effectsActive: effectsManager.active
    readonly property bool effectsPending: effectsManager.pending
    readonly property string effectsApplyState: effectsManager.applyState
    readonly property string effectsError: effectsManager.lastError
    readonly property string effectsGeneratedPath: effectsManager.generatedPath
    readonly property bool effectsEngineInstalled: effectsManager.engineDetector.installed
    readonly property bool effectsOverrideActive: effectsManager.compatibility.overrideActive
    readonly property string hyprlandVersion: runtimeDiagnostics.hyprlandVersion
    readonly property string hyprlandCommit: runtimeDiagnostics.hyprlandCommit
    readonly property string hyprlandAbi: runtimeDiagnostics.hyprlandAbi
    readonly property string nativeDecorationVersion: runtimeDiagnostics.nativeDecorationVersion
    readonly property int monitorCount: runtimeDiagnostics.monitors.length
    readonly property bool nativeDecorationLoaded: runtimeDiagnostics.nativeDecorationLoaded
    readonly property bool effectsEngineLoaded: runtimeDiagnostics.effectsEngineLoaded
    readonly property string effectsEngineVersion: runtimeDiagnostics.effectsEngineVersion
    readonly property string nativeApplyState: nativeBridge.state
    readonly property string decorationStyle: configStore.decorationStyle
    readonly property int lightWidth: configStore.lightWidth
    readonly property int darkWidth: configStore.darkWidth
    readonly property real shadeFactor: configStore.shadeFactor
    readonly property bool useThemeAccent: configStore.useThemeAccent
    readonly property string activeColor: configStore.activeColor
    readonly property string inactiveColor: configStore.inactiveColor
    readonly property real inactiveOpacity: configStore.inactiveOpacity
    readonly property string themeAccent: themeBridge.accentHex
    readonly property var applications: configStore.applications
    readonly property var runningApplications: hyprlandState.applicationList()
    readonly property var lastActiveApplication: hyprlandState.lastExternalSnapshot

    readonly property string trackerState: geometryTracker.state
    readonly property int sentinelHz: geometryTracker.sentinelHz
    readonly property int sampleCount: geometryTracker.sampleCount
    readonly property int transitionCount: geometryTracker.transitionCount
    readonly property bool hudShown: geometryTracker.shown
    readonly property bool hudImplemented: true

    function boolValue(value) {
        var text = String(value).toLowerCase()
        return value === true || text === "true" || text === "1" || text === "on"
    }

    function moduleEnabled(moduleName) {
        if (moduleName === "decorations") return root.decorationsEnabled
        if (moduleName === "hud") return root.hudEnabled
        if (moduleName === "effects") return root.effectsEnabled
        return false
    }

    function setModuleEnabled(moduleName, value) {
        var name = String(moduleName || "")
        var enabled = root.boolValue(value)
        if (!configStore.setModuleEnabled(name, enabled)) return "unknown-module"
        return enabled ? "enabled" : "disabled"
    }

    // Backward-compatible spike endpoint. It now controls Decorations explicitly.
    function setEnabled(value) {
        return root.setModuleEnabled("decorations", value)
    }

    function setDebug(value) {
        root.debugEnabled = root.boolValue(value)
        return root.debugEnabled ? "enabled" : "disabled"
    }

    function setSentinelHz(value) {
        var parsed = Math.round(Number(value))
        if (!isFinite(parsed)) return "invalid"
        geometryTracker.sentinelHz = Math.max(1, Math.min(60, parsed))
        return String(geometryTracker.sentinelHz)
    }

    function setDecorationSettings(valueJson) {
        try {
            var values = JSON.parse(String(valueJson || "{}"))
            if (!values || typeof values !== "object" || Array.isArray(values)) return "invalid"
            configStore.setDecorationSettings(values)
            return "ok"
        } catch (error) {
            return "invalid"
        }
    }

    function setEffectEvent(eventName, effectId) {
        return configStore.setEffectEvent(eventName, effectId) ? "ok" : "invalid"
    }

    function cycleEffect(eventName) {
        return effectsManager.cycleEffect(eventName)
    }

    function effectDisplayName(effectId) {
        return effectsManager.displayName(effectId)
    }

    function effectCompatibilityState(eventName, effectId) {
        return effectsManager.effectStatus(eventName, effectId)
    }

    function applyEffects() {
        return effectsManager.applyConfiguration() ? "applying" : "busy"
    }

    function testEffectsAnyway() {
        return effectsManager.testAnyway()
    }

    function clearEffectsOverride() {
        return effectsManager.clearOverride()
    }

    function applicationEffectOverride(appClass, eventName) {
        var classKey = String(appClass || "").toLowerCase()
        var eventKey = String(eventName || "")
        for (var index = 0; index < configStore.applications.length; index++) {
            var entry = configStore.applications[index]
            if (String(entry.appClass).toLowerCase() !== classKey) continue
            var overrides = entry.effectOverrides || {}
            return overrides[eventKey] === undefined ? "global" : String(overrides[eventKey])
        }
        return "global"
    }

    function cycleApplicationEffect(appClass, eventName) {
        var compatible = effectsManager.compatibleEffects(eventName)
        var choices = [{ id: "global", name: "Global" }]
        for (var index = 0; index < compatible.length; index++) choices.push(compatible[index])
        var current = root.applicationEffectOverride(appClass, eventName)
        var currentIndex = -1
        for (var choiceIndex = 0; choiceIndex < choices.length; choiceIndex++)
            if (choices[choiceIndex].id === current) currentIndex = choiceIndex
        var next = choices[(currentIndex + 1) % choices.length]
        return configStore.setApplicationEffectOverride(appClass, eventName, next.id)
            ? next.id : "invalid"
    }

    function setApplicationEffectOverride(appClass, eventName, effectId) {
        return configStore.setApplicationEffectOverride(appClass, eventName, effectId)
            ? "ok" : "invalid"
    }

    function addApplication(value) {
        return configStore.addApplication(value) ? "ok" : "invalid"
    }

    function addApplicationJson(valueJson) {
        try {
            var value = JSON.parse(String(valueJson || "{}"))
            return root.addApplication(value)
        } catch (error) {
            return "invalid"
        }
    }

    function addLastActiveApplication() {
        var value = root.lastActiveApplication || {}
        if (!value.visible || String(value.appClass || "") === "") return "unavailable"
        return root.addApplication({
            appClass: value.appClass,
            name: value.appClass,
            title: value.title,
            disableDecorations: true,
            disableHud: false,
            disableEffects: false
        })
    }

    function removeApplication(appClass) {
        return configStore.removeApplication(appClass) ? "ok" : "not-found"
    }

    function setApplicationExclusions(appClass, values) {
        return configStore.setApplicationExclusions(appClass, values) ? "ok" : "not-found"
    }

    function setApplicationExclusionsJson(appClass, valueJson) {
        try {
            var values = JSON.parse(String(valueJson || "{}"))
            return root.setApplicationExclusions(appClass, values)
        } catch (error) {
            return "invalid"
        }
    }

    function recordPanelOpened(payloadJson, identityMatched) {
        root.panelOpenCount += 1
        root.lastPanelPayload = String(payloadJson || "")
        root.panelServiceIdentityMatched = identityMatched === true
        geometryTracker.recordExternal("panel-open", {
            identityMatched: root.panelServiceIdentityMatched
        })
        runtimeDiagnostics.refresh()
    }

    function recordPanelClosed() {
        root.panelCloseCount += 1
        geometryTracker.recordExternal("panel-close", {})
    }

    function status() {
        var snapshot = geometryTracker.displaySnapshot || {}
        return JSON.stringify({
            pluginId: root.manifest && root.manifest.id ? String(root.manifest.id) : "omadecor",
            modules: {
                decorations: {
                    enabled: root.decorationsEnabled,
                    backend: "hyprland-native",
                    loaded: root.nativeDecorationLoaded,
                    applyState: nativeBridge.state,
                    error: nativeBridge.lastError,
                    style: configStore.decorationStyle,
                    registry: decorationRegistry.diagnostics(),
                    colorSource: configStore.useThemeAccent ? "theme-accent" : "manual",
                    themeAccent: themeBridge.accentHex
                },
                hud: {
                    enabled: root.hudEnabled,
                    implemented: root.hudImplemented,
                    state: geometryTracker.state,
                    shown: geometryTracker.shown,
                    host: hudHost.diagnostics(),
                    metrics: systemMetrics.diagnostics()
                },
                effects: {
                    enabled: root.effectsEnabled,
                    engineInstalled: effectsManager.engineDetector.installed,
                    engineLoaded: runtimeDiagnostics.effectsEngineLoaded,
                    engineName: runtimeDiagnostics.effectsEngineName,
                    engineVersion: runtimeDiagnostics.effectsEngineVersion,
                    engineAuthor: runtimeDiagnostics.effectsEngineAuthor,
                    engineDescription: runtimeDiagnostics.effectsEngineDescription,
                    compatibility: effectsManager.status,
                    allowed: effectsManager.allowed,
                    active: effectsManager.active,
                    overrideActive: effectsManager.compatibility.overrideActive,
                    events: configStore.effectsEvents,
                    manager: effectsManager.diagnostics()
                }
            },
            config: configStore.diagnostics(),
            runtime: runtimeDiagnostics.diagnostics(),
            nativeBridge: nativeBridge.diagnostics(),
            applications: configStore.applications,
            runningApplications: root.runningApplications,
            debug: root.debugEnabled,
            tracker: {
                sentinelHz: geometryTracker.sentinelHz,
                unstableHz: geometryTracker.unstableHz,
                stabilityWindowMs: geometryTracker.stabilityWindowMs,
                excludedClasses: geometryTracker.excludedClasses,
                sampleCount: geometryTracker.sampleCount,
                transitionCount: geometryTracker.transitionCount,
                geometry: snapshot.visible === true ? {
                    x: snapshot.x,
                    y: snapshot.y,
                    width: snapshot.width,
                    height: snapshot.height,
                    monitorId: snapshot.monitorId,
                    workspaceId: snapshot.workspaceId,
                    fullscreen: snapshot.fullscreen
                } : null
            },
            panel: {
                opens: root.panelOpenCount,
                closes: root.panelCloseCount,
                serviceIdentityMatched: root.panelServiceIdentityMatched,
                lastPayload: root.lastPanelPayload
            },
            source: hyprlandState.diagnostics(),
            surfaces: hudHost.surfaceCount > 0 ? [{
                module: "hud",
                kind: "layer-shell",
                count: hudHost.surfaceCount,
                clickThrough: true
            }] : []
        })
    }

    function refresh() {
        hyprlandState.refresh("ipc-refresh")
        runtimeDiagnostics.refresh()
        return "ok"
    }

    function reloadConfig() {
        configStore.reload()
        return "ok"
    }

    function resetConfig() {
        configStore.resetToDefaults()
        return "ok"
    }

    function trace() {
        return JSON.stringify(geometryTracker.trace)
    }

    function clearTrace() {
        geometryTracker.trace = []
        return "ok"
    }

    IpcHandler {
        target: "omadecor"

        function status(): string {
            return root.status()
        }

        function setModuleEnabled(moduleName: string, value: string): string {
            return root.setModuleEnabled(moduleName, value)
        }

        function setDecorationSettings(valueJson: string): string {
            return root.setDecorationSettings(valueJson)
        }

        function setEffectEvent(eventName: string, effectId: string): string {
            return root.setEffectEvent(eventName, effectId)
        }

        function applyEffects(): string {
            return root.applyEffects()
        }

        function testEffectsAnyway(): string {
            return root.testEffectsAnyway()
        }

        function clearEffectsOverride(): string {
            return root.clearEffectsOverride()
        }

        function addApplication(valueJson: string): string {
            return root.addApplicationJson(valueJson)
        }

        function addLastActiveApplication(): string {
            return root.addLastActiveApplication()
        }

        function removeApplication(appClass: string): string {
            return root.removeApplication(appClass)
        }

        function setApplicationExclusions(appClass: string, valueJson: string): string {
            return root.setApplicationExclusionsJson(appClass, valueJson)
        }

        function setApplicationEffectOverride(appClass: string, eventName: string, effectId: string): string {
            return root.setApplicationEffectOverride(appClass, eventName, effectId)
        }

        function reloadConfig(): string {
            return root.reloadConfig()
        }

        function resetConfig(): string {
            return root.resetConfig()
        }

        function trace(): string {
            return root.trace()
        }

        function clearTrace(): string {
            return root.clearTrace()
        }

        function setEnabled(value: string): string {
            return root.setEnabled(value)
        }

        function setDebug(value: string): string {
            return root.setDebug(value)
        }

        function setSentinelHz(value: string): string {
            return root.setSentinelHz(value)
        }

        function refresh(): string {
            return root.refresh()
        }
    }

    ConfigStore {
        id: configStore
    }

    RuntimeDiagnostics {
        id: runtimeDiagnostics
    }

    ThemeBridge {
        id: themeBridge
    }

    NativeDecorationRegistry {
        id: decorationRegistry
    }

    NativeBridge {
        id: nativeBridge
        config: configStore
        runtimeAvailable: runtimeDiagnostics.nativeDecorationLoaded
        themeAccent: themeBridge.accentHex
    }

    EffectsManager {
        id: effectsManager
        config: configStore
        runtime: runtimeDiagnostics
    }

    Connections {
        target: configStore

        function onConfigurationLoaded() {
            nativeBridge.applyConfiguration()
        }

        function onConfigurationChanged() {
            nativeBridge.applyConfiguration()
            if (root.hudEnabled) Qt.callLater(function() {
                hyprlandState.refresh("configuration-changed")
            })
        }
    }

    Connections {
        target: runtimeDiagnostics

        function onRefreshed() {
            nativeBridge.applyConfiguration()
        }
    }

    Connections {
        target: effectsManager.compatibility

        function onNotificationRequested(title, body) {
            Quickshell.execDetached([
                "/usr/share/omarchy/bin/omarchy-notification-send",
                "--app-name", "OmaDecor",
                title,
                body
            ])
        }
    }

    Connections {
        target: themeBridge

        function onAccentHexChanged() {
            if (configStore.useThemeAccent) nativeBridge.applyConfiguration()
        }
    }

    HyprlandState {
        id: hyprlandState
        debugEnabled: root.debugEnabled
    }

    GeometryTracker {
        id: geometryTracker
        source: hyprlandState
        enabled: root.hudEnabled
        debugEnabled: root.debugEnabled
        excludedClasses: configStore.hudClassExclusions
    }

    SystemMetrics {
        id: systemMetrics
        enabled: root.hudEnabled
    }

    HudHost {
        id: hudHost
        enabled: root.hudEnabled
        tracker: geometryTracker
        metrics: systemMetrics
        monitors: runtimeDiagnostics.monitors
    }

    Component.onCompleted: {
        Hyprland.refreshMonitors()
        hyprlandState.refresh("service-start")
    }
}

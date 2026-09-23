import QtQuick
import Quickshell
import "backends" as Backends

Scope {
    id: root

    property var config: null
    property var runtime: null
    property bool applyQueued: false
    property bool restoreQueued: false

    readonly property alias catalog: shaderCatalog
    readonly property alias backend: hyprWindowShadeBackend
    readonly property var engineDetector: hyprWindowShadeBackend.detector
    readonly property var compatibility: hyprWindowShadeBackend.compatibility
    readonly property string status: hyprWindowShadeBackend.status
    readonly property bool allowed: hyprWindowShadeBackend.allowed
    readonly property bool active: hyprWindowShadeBackend.active
    readonly property alias pending: hyprWindowShadeBackend.pending
    readonly property alias applyState: hyprWindowShadeBackend.applyState
    readonly property alias lastError: hyprWindowShadeBackend.lastError
    readonly property alias lastAppliedAtMs: hyprWindowShadeBackend.lastAppliedAtMs
    readonly property alias generatedPath: hyprWindowShadeBackend.generatedPath

    signal applied(bool success)

    function displayName(effectId) {
        return shaderCatalog.displayName(effectId)
    }

    function compatibleEffects(eventName) {
        return shaderCatalog.compatible(eventName)
    }

    function refreshCatalog() {
        shaderCatalog.refreshExternalPack()
    }

    function effectStatus(eventName, effectId) {
        return hyprWindowShadeBackend.validateEffect(effectId, eventName)
    }

    function effectiveEvents() {
        var result = ({})
        if (!config) return result
        for (var eventName in config.effectsEvents) {
            var effectId = String(config.effectsEvents[eventName] || "none")
            result[eventName] = root.effectStatus(eventName, effectId) === "BROKEN"
                ? "none" : effectId
        }
        return result
    }

    function effectiveApplications() {
        if (!config) return []
        var result = []
        for (var index = 0; index < config.applications.length; index++) {
            var source = config.applications[index] || {}
            var overrides = ({})
            var sourceOverrides = source.effectOverrides || {}
            for (var eventName in sourceOverrides) {
                var effectId = String(sourceOverrides[eventName] || "none")
                overrides[eventName] = root.effectStatus(eventName, effectId) === "BROKEN"
                    ? "none" : effectId
            }
            result.push({
                appClass: source.appClass,
                disableEffects: source.disableEffects === true,
                effectOverrides: overrides
            })
        }
        return result
    }

    function cycleEffect(eventName) {
        if (!config) return "unavailable"
        var choices = shaderCatalog.compatible(eventName)
        if (choices.length === 0) return "unavailable"
        var current = String(config.effectsEvents[eventName] || "none")
        var currentIndex = -1
        for (var index = 0; index < choices.length; index++)
            if (choices[index].id === current) currentIndex = index
        var next = choices[(currentIndex + 1) % choices.length]
        config.setEffectEvent(eventName, next.id)
        return next.id
    }

    function applyConfiguration() {
        if (!config || !config.loaded) return false
        root.applyQueued = true
        shaderCatalog.effectPackRegistry.refresh()
        return true
    }

    function restoreConfiguration() {
        if (!config || !config.loaded || !config.effectsEnabled) return false
        root.restoreQueued = true
        shaderCatalog.effectPackRegistry.refresh()
        return true
    }

    function testAnyway() {
        return hyprWindowShadeBackend.testAnyway()
    }

    function clearOverride() {
        return hyprWindowShadeBackend.clearOverride()
    }

    function diagnostics() {
        var result = hyprWindowShadeBackend.diagnostics()
        result.packInstalled = shaderCatalog.externalPackInstalled
        result.packPairs = shaderCatalog.externalPairCount
        result.packPath = shaderCatalog.externalPackRoot
        result.effectPacks = shaderCatalog.effectPackRegistry.diagnostics()
        return result
    }

    ShaderCatalog {
        id: shaderCatalog
        config: root.config
        backendCapabilities: hyprWindowShadeBackend.capabilities()
    }

    Connections {
        target: shaderCatalog.effectPackRegistry
        function onRefreshed() {
            if (shaderCatalog.effectPackRegistry.refreshPending) return
            if (root.applyQueued) {
                Qt.callLater(function() {
                    if (root.applyQueued && hyprWindowShadeBackend.applyConfiguration()) {
                        root.applyQueued = false
                        root.restoreQueued = false
                    }
                })
            } else if (root.restoreQueued) {
                Qt.callLater(function() {
                    if (root.restoreQueued && hyprWindowShadeBackend.restoreConfiguration())
                        root.restoreQueued = false
                })
            }
        }
    }

    Backends.HyprWindowShadeBackend {
        id: hyprWindowShadeBackend
        config: root.config
        runtime: root.runtime
        catalog: shaderCatalog
        events: root.effectiveEvents()
        applications: root.effectiveApplications()
    }

    Connections {
        target: hyprWindowShadeBackend
        function onApplied(success) {
            root.applied(success)
            if (root.applyQueued && shaderCatalog.effectPackRegistry.state !== "scanning")
                Qt.callLater(function() {
                    if (root.applyQueued) shaderCatalog.effectPackRegistry.refresh()
                })
            else if (root.restoreQueued && !root.applyQueued)
                Qt.callLater(function() {
                    if (root.restoreQueued && hyprWindowShadeBackend.restoreConfiguration())
                        root.restoreQueued = false
                })
        }
    }

    Connections {
        target: hyprWindowShadeBackend.compatibility
        function onEffectsAllowedChanged() {
            if (root.config && root.config.loaded && root.config.effectsEnabled
                    && !hyprWindowShadeBackend.allowed)
                root.applyConfiguration()
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import "RuleGenerator.js" as RuleGenerator

Scope {
    id: root

    property var config: null
    property var runtime: null
    property bool pending: false
    property string applyState: "idle"
    property string lastError: ""
    property double lastAppliedAtMs: 0
    property string pendingText: ""
    property string stdoutText: ""
    property string stderrText: ""
    property bool restoreRequested: false
    property bool engineReloadAttempted: false

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string generatedPath: configHome + "/hypr/omadecor.lua"
    readonly property alias catalog: shaderCatalog
    readonly property alias engineDetector: engineDetector
    readonly property alias compatibility: compatibility
    readonly property string status: compatibility.status
    readonly property bool allowed: compatibility.effectsAllowed
    readonly property bool active: config && config.effectsEnabled && allowed

    signal applied(bool success)

    function displayName(effectId) {
        return shaderCatalog.displayName(effectId)
    }

    function compatibleEffects(eventName) {
        return shaderCatalog.compatible(eventName)
    }

    function effectStatus(eventName, effectId) {
        return compatibility.effectStatus(effectId, eventName)
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
        root.pending = true
        return next.id
    }

    function testAnyway() {
        if (!config || compatibility.status !== "UNTESTED" || compatibility.fingerprint === "")
            return "unavailable"
        config.setEffectsOverrideFingerprint(compatibility.fingerprint)
        root.pending = true
        return "ok"
    }

    function clearOverride() {
        if (!config) return "unavailable"
        config.setEffectsOverrideFingerprint("")
        root.pending = true
        return "ok"
    }

    function applyConfiguration() {
        if (!config || !config.loaded || symlinkCheck.running || mkdirProcess.running
                || reloadProcess.running || evalProcess.running)
            return false
        root.lastError = ""
        root.stdoutText = ""
        root.stderrText = ""
        root.applyState = "writing"
        root.pendingText = RuleGenerator.generate(
            root.active,
            root.effectiveEvents(),
            shaderCatalog.pathMap(),
            root.effectiveApplications(),
            shaderCatalog.passthroughPath()
        )
        symlinkCheck.running = true
        return true
    }

    function ensureEngineLoaded() {
        if (!config || !config.effectsEnabled || !engineDetector.installed
                || engineDetector.loaded || engineReloadProcess.running
                || root.engineReloadAttempted) return false
        root.engineReloadAttempted = true
        engineReloadProcess.running = true
        return true
    }

    function restoreConfiguration() {
        if (!config || !config.loaded || !config.effectsEnabled) return false
        root.restoreRequested = true
        restoreTimer.restart()
        return true
    }

    function luaLoadExpression() {
        return "dofile(" + RuleGenerator.luaString(root.generatedPath) + ")"
    }

    function diagnostics() {
        return {
            status: root.status,
            desiredEnabled: config ? config.effectsEnabled : false,
            allowed: root.allowed,
            active: root.active,
            overrideActive: compatibility.overrideActive,
            fingerprint: compatibility.fingerprint,
            engineInstalled: engineDetector.installed,
            engineLoaded: engineDetector.loaded,
            packInstalled: shaderCatalog.externalPackInstalled,
            packPairs: shaderCatalog.externalPairCount,
            packPath: shaderCatalog.externalPackRoot,
            pending: root.pending,
            applyState: root.applyState,
            generatedPath: root.generatedPath,
            error: root.lastError,
            lastAppliedAtMs: root.lastAppliedAtMs
        }
    }

    ShaderCatalog { id: shaderCatalog }

    EngineDetector {
        id: engineDetector
        runtime: root.runtime
    }

    CompatibilityManager {
        id: compatibility
        runtime: root.runtime
        config: root.config
        detector: engineDetector
    }

    Connections {
        target: root.config
        function onConfigurationChanged() {
            root.pending = true
            if (root.config.effectsEnabled) root.ensureEngineLoaded()
        }
    }

    Timer {
        id: restoreTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (root.ensureEngineLoaded()) return
            root.restoreRequested = false
            root.applyConfiguration()
        }
    }

    Process {
        id: engineReloadProcess
        command: ["/usr/bin/hyprpm", "reload", "-n"]
        // qmllint disable signal-handler-parameters
        onExited: function() {
            if (root.runtime) root.runtime.refresh()
            if (root.restoreRequested) restoreTimer.restart()
        }
    }

    Process {
        id: symlinkCheck
        command: ["/usr/bin/test", "-L", root.generatedPath]
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            if (exitCode === 0) {
                root.applyState = "error"
                root.lastError = "Refusing to write symlinked omadecor.lua"
                root.applied(false)
                return
            }
            if (exitCode !== 1) {
                root.applyState = "error"
                root.lastError = "Unable to validate omadecor.lua target"
                root.applied(false)
                return
            }
            mkdirProcess.running = true
        }
    }

    Process {
        id: mkdirProcess
        command: ["/usr/bin/mkdir", "-p", root.configHome + "/hypr"]
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.applyState = "error"
                root.lastError = "Unable to create Hyprland config directory"
                root.applied(false)
                return
            }
            if (String(generatedFile.text()) === root.pendingText) {
                root.applyState = "reloading"
                reloadProcess.running = true
            } else {
                generatedFile.setText(root.pendingText)
            }
        }
    }

    FileView {
        id: generatedFile
        path: root.generatedPath
        atomicWrites: true
        printErrors: false
        onSaved: {
            root.applyState = "reloading"
            reloadProcess.running = true
        }
    }

    Process {
        id: reloadProcess
        command: ["/usr/bin/hyprctl", "reload"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.stdoutText = String(text || "").trim()
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.stderrText = String(text || "").trim()
        }
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            var success = exitCode === 0 && root.stdoutText.toLowerCase().indexOf("error") === -1
            if (!success) {
                root.lastAppliedAtMs = Date.now()
                root.applyState = "error"
                root.lastError = root.stderrText || root.stdoutText || "Hyprland reload failed"
                root.applied(false)
                return
            }
            root.applyState = "evaluating"
            root.stdoutText = ""
            root.stderrText = ""
            evalProcess.command = ["/usr/bin/hyprctl", "eval", root.luaLoadExpression()]
            evalProcess.running = true
        }
    }

    Process {
        id: evalProcess
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.stdoutText = String(text || "").trim()
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.stderrText = String(text || "").trim()
        }
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            var success = exitCode === 0 && root.stdoutText.toLowerCase().indexOf("error") === -1
            root.lastAppliedAtMs = Date.now()
            root.applyState = success ? "applied" : "error"
            root.lastError = success ? "" : (root.stderrText || root.stdoutText || "Hyprland rejected generated effect rules")
            if (success) root.pending = false
            root.applied(success)
            if (root.runtime) root.runtime.refresh()
        }
    }
}

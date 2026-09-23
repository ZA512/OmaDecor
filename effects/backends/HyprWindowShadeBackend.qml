import QtQuick
import Quickshell
import Quickshell.Io
import ".." as Effects
import "HyprWindowShadeRuleGenerator.js" as RuleGenerator

Scope {
    id: root

    property var config: null
    property var runtime: null
    property var catalog: null
    property var events: ({})
    property var applications: []
    property bool pending: false
    property bool applying: false
    property int applyingRevision: -1
    property string applyState: "idle"
    property string lastError: ""
    property double lastAppliedAtMs: 0
    property string pendingText: ""
    property string stdoutText: ""
    property string stderrText: ""
    property string clientsText: ""
    property bool applyEnabled: false
    property bool restoreRequested: false
    property bool engineReloadAttempted: false

    readonly property string backendId: "hyprwindowshade"
    readonly property var capabilitySet: [
        "event.open", "event.close", "event.move", "event.resize",
        "event.workspace", "event.focus", "event.unfocus", "event.urgent",
        "event.float", "event.tile", "event.fullscreen-enter",
        "event.fullscreen-exit", "shader.progress", "shader.random-seed",
        "shader.window-texture", "shader.window-size", "shader.motion"
    ]
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string generatedPath: configHome + "/hypr/omadecor.lua"
    readonly property alias detector: engineDetector
    readonly property alias compatibility: compatibilityManager
    readonly property string status: compatibilityManager.status
    readonly property bool allowed: compatibilityManager.effectsAllowed
    readonly property bool active: config && config.effectsEnabled && allowed

    signal applied(bool success)

    function capabilities() {
        return root.capabilitySet.slice()
    }

    function probe() {
        return {
            backend: root.backendId,
            status: root.status,
            installed: engineDetector.installed,
            loaded: engineDetector.loaded,
            allowed: root.allowed,
            fingerprint: compatibilityManager.fingerprint
        }
    }

    function validateEffect(effectId, eventName) {
        return compatibilityManager.effectStatus(effectId, eventName)
    }

    function testAnyway() {
        if (!config || compatibilityManager.status !== "UNTESTED"
                || compatibilityManager.fingerprint === "") return "unavailable"
        config.setEffectsOverrideFingerprint(compatibilityManager.fingerprint)
        root.pending = true
        return "ok"
    }

    function clearOverride() {
        if (!config) return "unavailable"
        config.setEffectsOverrideFingerprint("")
        root.pending = true
        return "ok"
    }

    function beginApply(enabled) {
        if (!config || !config.loaded || !catalog || root.applying || symlinkCheck.running
                || clientsProcess.running || mkdirProcess.running || reloadProcess.running
                || evalProcess.running)
            return false
        root.applying = true
        root.lastError = ""
        root.stdoutText = ""
        root.stderrText = ""
        root.applyState = "writing"
        root.applyEnabled = enabled
        root.clientsText = ""
        clientsProcess.running = true
        return true
    }

    function preparePendingText() {
        root.applyingRevision = root.config.revision
        root.pendingText = RuleGenerator.generate(
            root.applyEnabled,
            root.events,
            root.config.effectsTimings,
            catalog.pathMap(),
            root.applications,
            catalog.passthroughPath(),
            generatedFile.text(),
            root.clientsText,
            catalog.managedShaderRoots()
        )
        symlinkCheck.running = true
    }

    function applyConfiguration() {
        return root.beginApply(root.active)
    }

    function deactivate() {
        return root.beginApply(false)
    }

    function ensureLoaded() {
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
            backend: root.backendId,
            capabilities: root.capabilities(),
            status: root.status,
            desiredEnabled: config ? config.effectsEnabled : false,
            allowed: root.allowed,
            active: root.active,
            overrideActive: compatibilityManager.overrideActive,
            fingerprint: compatibilityManager.fingerprint,
            engineInstalled: engineDetector.installed,
            engineLoaded: engineDetector.loaded,
            pending: root.pending,
            applyState: root.applyState,
            generatedPath: root.generatedPath,
            error: root.lastError,
            lastAppliedAtMs: root.lastAppliedAtMs
        }
    }

    Effects.EngineDetector {
        id: engineDetector
        runtime: root.runtime
    }

    Effects.CompatibilityManager {
        id: compatibilityManager
        runtime: root.runtime
        config: root.config
        detector: engineDetector
    }

    Connections {
        target: root.config
        function onConfigurationChanged() {
            root.pending = true
            if (root.config.effectsEnabled) root.ensureLoaded()
        }
    }

    Timer {
        id: restoreTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (root.ensureLoaded()) return
            if (!root.applyConfiguration()) {
                restoreTimer.restart()
                return
            }
            root.restoreRequested = false
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
        id: clientsProcess
        command: ["/usr/bin/hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.clientsText = String(text || "")
        }
        // qmllint disable signal-handler-parameters
        onExited: function() { root.preparePendingText() }
    }

    Process {
        id: symlinkCheck
        command: ["/usr/bin/test", "-L", root.generatedPath]
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            if (exitCode === 0) {
                root.applyState = "error"
                root.lastError = "Refusing to write symlinked omadecor.lua"
                root.applying = false
                root.applied(false)
                return
            }
            if (exitCode !== 1) {
                root.applyState = "error"
                root.lastError = "Unable to validate omadecor.lua target"
                root.applying = false
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
                root.applying = false
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
            var success = exitCode === 0
                && root.stdoutText.toLowerCase().indexOf("error") === -1
            if (!success) {
                root.lastAppliedAtMs = Date.now()
                root.applyState = "error"
                root.lastError = root.stderrText || root.stdoutText || "Hyprland reload failed"
                root.applying = false
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
            var success = exitCode === 0
                && root.stdoutText.toLowerCase().indexOf("error") === -1
            root.lastAppliedAtMs = Date.now()
            root.applyState = success ? "applied" : "error"
            root.lastError = success ? ""
                : (root.stderrText || root.stdoutText
                    || "Hyprland rejected generated effect rules")
            if (success && root.config.revision === root.applyingRevision)
                root.pending = false
            root.applying = false
            root.applied(success)
            if (root.runtime) root.runtime.refresh()
        }
    }
}

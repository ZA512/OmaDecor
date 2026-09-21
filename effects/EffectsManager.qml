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
        if (!config || !config.loaded || symlinkCheck.running || mkdirProcess.running || reloadProcess.running)
            return false
        root.lastError = ""
        root.applyState = "writing"
        root.pendingText = RuleGenerator.generate(
            root.active,
            config.effectsEvents,
            shaderCatalog.pathMap(),
            config.effectsExcludedClasses(),
            shaderCatalog.passthroughPath()
        )
        symlinkCheck.running = true
        return true
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
        function onConfigurationChanged() { root.pending = true }
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
            generatedFile.setText(root.pendingText)
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
            root.lastAppliedAtMs = Date.now()
            root.applyState = success ? "applied" : "error"
            root.lastError = success ? "" : (root.stderrText || root.stdoutText || "Hyprland reload failed")
            if (success) root.pending = false
            root.applied(success)
            if (root.runtime) root.runtime.refresh()
        }
    }
}

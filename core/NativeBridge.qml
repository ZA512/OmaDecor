import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var config: null
    property bool runtimeAvailable: false
    property string themeAccent: "#47d7ff"
    property string state: "idle"
    property string lastError: ""
    property double lastAppliedAtMs: 0
    property bool applyQueued: false
    property string stdoutText: ""
    property string stderrText: ""
    readonly property string builtinThemePath: root.localFilePath(
        Qt.resolvedUrl("../decorations/styles/raised-edge.omadecor.json")
    )
    property string themePath: root.builtinThemePath
    property var themeParameters: ({})

    signal applied(bool success)

    function colorValue(value, fallback, opacity) {
        var text = String(value || "")
        if (!/^#[0-9a-fA-F]{6}$/.test(text)) text = fallback
        var alpha = Math.max(0, Math.min(1, Number(opacity)))
        if (!isFinite(alpha) || alpha >= 0.999) return "rgb(" + text.slice(1).toLowerCase() + ")"
        var alphaHex = Math.round(alpha * 255).toString(16)
        if (alphaHex.length < 2) alphaHex = "0" + alphaHex
        return "rgba(" + text.slice(1).toLowerCase() + alphaHex + ")"
    }

    function effectiveActiveColor() {
        if (!root.config) return "#47d7ff"
        return root.config.useThemeAccent === true ? root.themeAccent : root.config.activeColor
    }

    function classList() {
        if (!root.config) return ""
        var classes = typeof root.config.decorationExcludedClasses === "function"
            ? root.config.decorationExcludedClasses() : root.config.excludedClasses
        if (!Array.isArray(classes)) return ""
        var result = []
        for (var index = 0; index < classes.length; index++) {
            var entry = String(classes[index] || "").trim()
            if (entry !== "" && /^[A-Za-z0-9._:+-]{1,128}$/.test(entry)) result.push(entry)
        }
        return result.join(",")
    }

    function quotedLuaString(value) {
        return "\"" + String(value).replace(/\\/g, "\\\\").replace(/\"/g, "\\\"") + "\""
    }

    function localFilePath(value) {
        var text = String(value || "")
        if (text.indexOf("file://") === 0) text = text.slice(7)
        try {
            return decodeURIComponent(text)
        } catch (error) {
            return text
        }
    }

    function borderOnlyScript() {
        var borderSize = root.config ? Math.max(0, Math.min(20, Math.round(root.config.stockBorderSize))) : 5
        return "hl.config({ general = { border_size = " + borderSize + " } })"
    }

    function themeParametersJson() {
        return JSON.stringify(root.themeParameters || {})
    }

    function fullScript() {
        var enabled = root.config && root.config.decorationsEnabled === true
        var lightWidth = Math.max(0, Math.min(20, Math.round(root.config.lightWidth)))
        var darkWidth = Math.max(0, Math.min(20, Math.round(root.config.darkWidth)))
        var shadeFactor = Math.max(0, Math.min(1, Number(root.config.shadeFactor)))
        var borderSize = enabled ? 0 : Math.max(0, Math.min(20, Math.round(root.config.stockBorderSize)))
        var effectiveActive = root.effectiveActiveColor()
        var activeColor = root.colorValue(effectiveActive, "#47d7ff", 1)
        var inactiveBase = root.config.useThemeAccent === true ? effectiveActive : root.config.inactiveColor
        var inactiveColor = root.colorValue(inactiveBase, "#64748b", root.config.inactiveOpacity)
        var excluded = root.quotedLuaString(root.classList())

        return "hl.config({ general = { border_size = " + borderSize
            + " }, plugin = { omadecor = { enabled = " + (enabled ? "true" : "false")
            + ", light_width = " + lightWidth
            + ", dark_width = " + darkWidth
            + ", shade_factor = " + shadeFactor
            + ", inactive_opacity = " + Math.max(0, Math.min(1, Number(root.config.inactiveOpacity)))
            + ", theme_path = " + root.quotedLuaString(root.themePath)
            + ", theme_parameters = " + root.quotedLuaString(root.themeParametersJson())
            + ", excluded_classes = " + excluded
            + ", col = { active = \"" + activeColor + "\", inactive = \"" + inactiveColor + "\" } } } })"
    }

    function applyConfiguration() {
        if (!root.config || !root.config.loaded) return false
        if (applyProcess.running) {
            root.applyQueued = true
            return true
        }

        root.applyQueued = false
        root.stdoutText = ""
        root.stderrText = ""
        root.lastError = ""
        root.state = "applying"
        applyProcess.command = [
            "/usr/bin/hyprctl",
            "eval",
            root.runtimeAvailable ? root.fullScript() : root.borderOnlyScript()
        ]
        applyProcess.running = true
        return true
    }

    function diagnostics() {
        return {
            state: root.state,
            runtimeAvailable: root.runtimeAvailable,
            colorSource: root.config && root.config.useThemeAccent === true ? "theme-accent" : "manual",
            effectiveActiveColor: root.effectiveActiveColor(),
            themePath: root.themePath,
            themeParameters: root.themeParameters,
            excludedClassCount: root.classList() === "" ? 0 : root.classList().split(",").length,
            error: root.lastError,
            lastAppliedAtMs: root.lastAppliedAtMs
        }
    }

    Process {
        id: applyProcess
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
            if (success) {
                root.state = root.runtimeAvailable ? "applied" : "fallback-border-restored"
                root.lastError = ""
            } else {
                root.state = "error"
                root.lastError = root.stderrText || root.stdoutText || "Hyprland rejected the native configuration"
            }
            root.applied(success)
            if (root.applyQueued) Qt.callLater(root.applyConfiguration)
        }
    }
}

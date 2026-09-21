import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool refreshing: false
    property bool pluginsFinished: false
    property bool versionFinished: false
    property bool monitorsFinished: false
    property string lastError: ""
    property double lastRefreshedAtMs: 0

    property bool nativeDecorationLoaded: false
    property string nativeDecorationVersion: ""
    property bool effectsEngineLoaded: false
    property string effectsEngineName: ""
    property string effectsEngineVersion: ""
    property string effectsEngineAuthor: ""
    property string effectsEngineDescription: ""

    property string hyprlandVersion: ""
    property string hyprlandCommit: ""
    property string hyprlandAbi: ""
    property var monitors: []

    signal refreshed()

    function finishIfReady() {
        if (!root.pluginsFinished || !root.versionFinished || !root.monitorsFinished) return
        root.refreshing = false
        root.lastRefreshedAtMs = Date.now()
        root.refreshed()
    }

    function parsePlugins(rawText) {
        root.nativeDecorationLoaded = false
        root.nativeDecorationVersion = ""
        root.effectsEngineLoaded = false
        root.effectsEngineName = ""
        root.effectsEngineVersion = ""
        root.effectsEngineAuthor = ""
        root.effectsEngineDescription = ""
        try {
            var plugins = JSON.parse(String(rawText || "[]"))
            if (!Array.isArray(plugins)) throw new Error("plugin list is not an array")
            for (var index = 0; index < plugins.length; index++) {
                var plugin = plugins[index] || {}
                var name = String(plugin.name || "")
                if (name === "omadecor-native") {
                    root.nativeDecorationLoaded = true
                    root.nativeDecorationVersion = String(plugin.version || "")
                }
                if (name.toLowerCase() === "hyprwindowshade") {
                    root.effectsEngineLoaded = true
                    root.effectsEngineName = name
                    root.effectsEngineVersion = String(plugin.version || "")
                    root.effectsEngineAuthor = String(plugin.author || "")
                    root.effectsEngineDescription = String(plugin.description || "")
                }
            }
        } catch (error) {
            root.lastError = "Plugin diagnostics failed: " + String(error)
        }
        root.pluginsFinished = true
        root.finishIfReady()
    }

    function parseVersion(rawText) {
        try {
            var version = JSON.parse(String(rawText || "{}"))
            root.hyprlandVersion = String(version.version || "")
            root.hyprlandCommit = String(version.commit || "")
            root.hyprlandAbi = String(version.abiHash || "")
        } catch (error) {
            root.lastError = "Hyprland version diagnostics failed: " + String(error)
        }
        root.versionFinished = true
        root.finishIfReady()
    }

    function parseMonitors(rawText) {
        var result = []
        try {
            var values = JSON.parse(String(rawText || "[]"))
            if (!Array.isArray(values)) throw new Error("monitor list is not an array")
            for (var index = 0; index < values.length; index++) {
                var monitor = values[index] || {}
                if (monitor.disabled === true) continue
                result.push({
                    id: Number(monitor.id),
                    name: String(monitor.name || ""),
                    x: Number(monitor.x),
                    y: Number(monitor.y),
                    width: Number(monitor.width),
                    height: Number(monitor.height),
                    scale: Number(monitor.scale),
                    transform: Number(monitor.transform)
                })
            }
            root.monitors = result
        } catch (error) {
            root.lastError = "Monitor diagnostics failed: " + String(error)
        }
        root.monitorsFinished = true
        root.finishIfReady()
    }

    function refresh() {
        if (pluginsProcess.running || versionProcess.running || monitorsProcess.running) return false
        root.refreshing = true
        root.pluginsFinished = false
        root.versionFinished = false
        root.monitorsFinished = false
        root.lastError = ""
        pluginsProcess.running = true
        versionProcess.running = true
        monitorsProcess.running = true
        return true
    }

    function diagnostics() {
        return {
            refreshing: root.refreshing,
            error: root.lastError,
            lastRefreshedAtMs: root.lastRefreshedAtMs,
            hyprland: {
                version: root.hyprlandVersion,
                commit: root.hyprlandCommit,
                abi: root.hyprlandAbi
            },
            decoration: {
                loaded: root.nativeDecorationLoaded,
                version: root.nativeDecorationVersion
            },
            effects: {
                loaded: root.effectsEngineLoaded,
                name: root.effectsEngineName,
                version: root.effectsEngineVersion,
                author: root.effectsEngineAuthor,
                description: root.effectsEngineDescription
            },
            monitors: root.monitors
        }
    }

    Process {
        id: pluginsProcess
        command: ["/usr/bin/hyprctl", "-j", "plugin", "list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parsePlugins(text)
        }
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            if (exitCode === 0 || root.pluginsFinished) return
            root.lastError = "Unable to query loaded Hyprland plugins"
            root.pluginsFinished = true
            root.finishIfReady()
        }
    }

    Process {
        id: versionProcess
        command: ["/usr/bin/hyprctl", "-j", "version"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseVersion(text)
        }
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            if (exitCode === 0 || root.versionFinished) return
            root.lastError = "Unable to query the Hyprland version"
            root.versionFinished = true
            root.finishIfReady()
        }
    }


    Process {
        id: monitorsProcess
        command: ["/usr/bin/hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseMonitors(text)
        }
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            if (exitCode === 0 || root.monitorsFinished) return
            root.lastError = "Unable to query Hyprland monitors"
            root.monitorsFinished = true
            root.finishIfReady()
        }
    }

    Component.onCompleted: root.refresh()
}

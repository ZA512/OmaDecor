import QtQuick
import Quickshell
import Quickshell.Io
import "EffectValidator.js" as EffectValidator

Scope {
    id: root

    property var config: null
    property var backendCapabilities: []
    readonly property var eventNames: [
        "open", "close", "move", "resize", "workspace", "fullscreenEnter",
        "fullscreenExit", "float", "tile", "focus", "unfocus", "urgent"
    ]
    readonly property var builtinEffects: [
        {
            id: "none", name: "None", events: root.eventNames, path: "",
            source: "builtin", pack: "OmaDecor", license: "MIT",
            description: "Disable the effect for this event."
        },
        {
            id: "simple-fade-open", name: "Simple Fade", events: ["open"],
            path: root.shaderPath("simple-fade-open.glsl"), source: "builtin",
            pack: "OmaDecor", license: "MIT", description: "Quick opacity fade in."
        },
        {
            id: "simple-fade-close", name: "Simple Fade", events: ["close"],
            path: root.shaderPath("simple-fade-close.glsl"), source: "builtin",
            pack: "OmaDecor", license: "MIT", description: "Quick opacity fade out."
        },
        {
            id: "soft-focus-pulse", name: "Soft Pulse",
            events: ["focus", "unfocus", "urgent"],
            path: root.shaderPath("soft-focus-pulse.glsl"), source: "builtin",
            pack: "OmaDecor", license: "MIT", description: "Brief brightness pulse."
        },
        {
            id: "simple-wobble", name: "Soft Wobble",
            events: ["move", "resize", "workspace", "fullscreenEnter", "fullscreenExit", "float", "tile"],
            path: root.shaderPath("simple-wobble.glsl"), source: "builtin",
            pack: "OmaDecor", license: "MIT", description: "Velocity-driven window deformation."
        }
    ]
    property var packEffects: []
    property string externalScanOutput: ""
    property bool externalScanPending: false
    readonly property alias effectPackRegistry: effectPackRegistry
    readonly property var effects: root.builtinEffects
        .concat(effectPackRegistry.effects)
        .concat(root.packEffects)
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME")
        || (Quickshell.env("HOME") + "/.local/share")
    readonly property string externalPackRoot: root.dataHome
        + "/omadecor/shader-packs/hyprland-shader"
    readonly property string externalShaderDir: root.externalPackRoot + "/shaders"
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")
    readonly property string externalPreviewDir: root.cacheHome
        + "/omadecor/effects/previews/hyprland-shader"
    readonly property string externalScannerPath: root.localFilePath(
        Qt.resolvedUrl("../scripts/scan-external-shaders.sh"))
    readonly property bool externalPackInstalled: root.packEffects.length > 0
    property int externalPairCount: 0

    function shaderPath(fileName) {
        var value = Qt.resolvedUrl("shaders/" + fileName).toString()
        if (value.indexOf("file://") === 0) return decodeURIComponent(value.slice(7))
        return value
    }

    function localFilePath(value) {
        var text = String(value || "")
        if (text.indexOf("file://") === 0) text = text.slice(7)
        try { return decodeURIComponent(text) }
        catch (error) { return text }
    }

    function passthroughPath() {
        return root.shaderPath("passthrough.glsl")
    }

    function managedShaderRoots() {
        var shaderDirectory = root.shaderPath("passthrough.glsl")
        var split = shaderDirectory.lastIndexOf("/shaders/")
        var roots = [root.cacheHome + "/omadecor/effects/",
            root.dataHome + "/omadecor/shader-packs/"]
        if (split !== -1) roots.push(shaderDirectory.slice(0, split) + "/")
        return roots
    }

    function titleForBase(baseName) {
        var words = String(baseName || "").replace(/[-_]+/g, " ").split(" ")
        for (var index = 0; index < words.length; index++) {
            if (words[index] === "") continue
            words[index] = words[index].charAt(0).toUpperCase() + words[index].slice(1)
        }
        return words.join(" ")
    }

    function rebuildExternalPack(lines) {
        var result = []
        var seenIds = ({})
        var pairEvents = ({})
        for (var index = 0; index < lines.length; index++) {
            var record
            try { record = JSON.parse(String(lines[index] || "")) }
            catch (error) { continue }
            var baseName = String(record.base || "")
            var eventName = String(record.event || "")
            if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(baseName)
                    || (eventName !== "open" && eventName !== "close")) continue
            var previewName = String(record.preview || "")
            if (!/^[a-z0-9][a-z0-9-]{0,63}-[0-9a-f]{16}\.gif$/.test(previewName)
                    || previewName.indexOf(baseName + "-") !== 0) previewName = ""
            var effectId = "hyprland-shader." + baseName + "." + eventName
            if (seenIds[effectId]) continue
            seenIds[effectId] = true
            if (!pairEvents[baseName]) pairEvents[baseName] = ({})
            pairEvents[baseName][eventName] = true
            result.push({
                id: effectId,
                name: root.titleForBase(baseName),
                events: [eventName],
                path: root.externalShaderDir + "/" + baseName + "_" + eventName + ".glsl",
                source: "external",
                pack: "Hyprland-Shader",
                author: "jbuck95 / upstream authors",
                license: "External pack — see LICENSE",
                description: eventName === "open" ? "Open animation" : "Close animation",
                preview: previewName === "" ? ""
                    : root.externalPreviewDir + "/" + previewName
            })
        }
        result.sort(function(left, right) {
            if (left.name < right.name) return -1
            if (left.name > right.name) return 1
            return left.id < right.id ? -1 : 1
        })
        var pairCount = 0
        for (var pairName in pairEvents)
            if (pairEvents[pairName].open && pairEvents[pairName].close) pairCount++
        root.packEffects = result
        root.externalPairCount = pairCount
    }

    function refreshExternalPack() {
        effectPackRegistry.refresh()
        root.packEffects = []
        root.externalPairCount = 0
        if (externalScanProcess.running) {
            root.externalScanPending = true
            return
        }
        root.externalScanOutput = ""
        externalScanProcess.running = true
    }

    function findEffect(effectId) {
        for (var index = 0; index < root.effects.length; index++)
            if (root.effects[index].id === effectId) return root.effects[index]
        return null
    }

    function effect(effectId) {
        return root.findEffect(effectId) || root.builtinEffects[0]
    }

    function compatible(eventName) {
        var result = []
        for (var index = 0; index < root.effects.length; index++) {
            var entry = root.effects[index]
            if (entry.events.indexOf(eventName) !== -1 && root.requirementsSatisfied(entry))
                result.push(entry)
        }
        return result
    }

    function requirementsSatisfied(entry) {
        return EffectValidator.missingCapabilities(entry, root.backendCapabilities).length === 0
    }

    function isCompatible(eventName, effectId) {
        var entry = root.findEffect(effectId)
        return !!entry && entry.events.indexOf(eventName) !== -1
            && root.requirementsSatisfied(entry)
    }

    function displayName(effectId) {
        var entry = root.findEffect(effectId)
        return entry ? entry.name : "Missing effect"
    }

    function pathMap() {
        var result = ({})
        for (var index = 0; index < root.effects.length; index++)
            result[root.effects[index].id] = root.effects[index].path
        return result
    }

    Process {
        id: externalScanProcess
        command: [
            "/usr/bin/bash", root.externalScannerPath,
            root.externalShaderDir, root.externalPreviewDir
        ]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.externalScanOutput = String(text || "")
        }
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            if (exitCode === 0)
                root.rebuildExternalPack(root.externalScanOutput.split("\n"))
            if (root.externalScanPending) {
                root.externalScanPending = false
                Qt.callLater(root.refreshExternalPack)
            }
        }
    }

    EffectPackRegistry { id: effectPackRegistry; config: root.config }

    Component.onCompleted: root.refreshExternalPack()
}

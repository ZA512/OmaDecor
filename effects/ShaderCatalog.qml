import QtQuick
import Qt.labs.folderlistmodel
import Quickshell

Scope {
    id: root

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
    readonly property var effects: root.builtinEffects.concat(root.packEffects)
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME")
        || (Quickshell.env("HOME") + "/.local/share")
    readonly property string externalPackRoot: root.dataHome
        + "/omadecor/shader-packs/hyprland-shader"
    readonly property string externalShaderDir: root.externalPackRoot + "/shaders"
    readonly property bool externalPackInstalled: root.packEffects.length > 0
    readonly property int externalPairCount: Math.floor(root.packEffects.length / 2)

    function shaderPath(fileName) {
        var value = Qt.resolvedUrl("shaders/" + fileName).toString()
        if (value.indexOf("file://") === 0) return decodeURIComponent(value.slice(7))
        return value
    }

    function passthroughPath() {
        return root.shaderPath("passthrough.glsl")
    }

    function titleForBase(baseName) {
        var words = String(baseName || "").replace(/[-_]+/g, " ").split(" ")
        for (var index = 0; index < words.length; index++) {
            if (words[index] === "") continue
            words[index] = words[index].charAt(0).toUpperCase() + words[index].slice(1)
        }
        return words.join(" ")
    }

    function rebuildExternalPack() {
        var result = []
        for (var index = 0; index < externalFiles.count; index++) {
            var fileName = String(externalFiles.get(index, "fileName") || "")
            var match = fileName.match(/^([a-z0-9][a-z0-9-]{0,63})_(open|close)\.glsl$/)
            if (!match) continue
            var baseName = match[1]
            var eventName = match[2]
            result.push({
                id: "hyprland-shader." + baseName + "." + eventName,
                name: root.titleForBase(baseName),
                events: [eventName],
                path: root.externalShaderDir + "/" + fileName,
                source: "external",
                pack: "Hyprland-Shader",
                author: "jbuck95 / upstream authors",
                license: "External pack — see LICENSE",
                description: eventName === "open" ? "Open animation" : "Close animation"
            })
        }
        result.sort(function(left, right) {
            if (left.name < right.name) return -1
            if (left.name > right.name) return 1
            return left.id < right.id ? -1 : 1
        })
        root.packEffects = result
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
            if (entry.events.indexOf(eventName) !== -1) result.push(entry)
        }
        return result
    }

    function isCompatible(eventName, effectId) {
        var entry = root.findEffect(effectId)
        return !!entry && entry.events.indexOf(eventName) !== -1
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

    FolderListModel {
        id: externalFiles
        folder: "file://" + root.externalShaderDir
        nameFilters: ["*_open.glsl", "*_close.glsl"]
        showFiles: true
        showDirs: false
        showDotAndDotDot: false
        showHidden: false
        showOnlyReadable: true
        sortField: FolderListModel.Name
        onCountChanged: root.rebuildExternalPack()
        onStatusChanged: root.rebuildExternalPack()
    }

    Component.onCompleted: root.rebuildExternalPack()
}

import QtQuick

QtObject {
    id: root

    readonly property var eventNames: [
        "open", "close", "move", "resize", "workspace", "fullscreenEnter",
        "fullscreenExit", "float", "tile", "focus", "unfocus", "urgent"
    ]
    readonly property var effects: [
        { id: "none", name: "None", events: root.eventNames, path: "" },
        { id: "simple-fade-open", name: "Simple Fade", events: ["open"], path: root.shaderPath("simple-fade-open.glsl") },
        { id: "simple-fade-close", name: "Simple Fade", events: ["close"], path: root.shaderPath("simple-fade-close.glsl") },
        { id: "soft-focus-pulse", name: "Soft Pulse", events: ["focus", "unfocus", "urgent"], path: root.shaderPath("soft-focus-pulse.glsl") },
        { id: "simple-wobble", name: "Soft Wobble", events: ["move", "resize", "workspace", "fullscreenEnter", "fullscreenExit", "float", "tile"], path: root.shaderPath("simple-wobble.glsl") }
    ]

    function shaderPath(fileName) {
        var value = Qt.resolvedUrl("shaders/" + fileName).toString()
        if (value.indexOf("file://") === 0) return decodeURIComponent(value.slice(7))
        return value
    }

    function passthroughPath() {
        return root.shaderPath("passthrough.glsl")
    }

    function effect(effectId) {
        for (var index = 0; index < root.effects.length; index++)
            if (root.effects[index].id === effectId) return root.effects[index]
        return root.effects[0]
    }

    function compatible(eventName) {
        var result = []
        for (var index = 0; index < root.effects.length; index++) {
            var entry = root.effects[index]
            if (entry.events.indexOf(eventName) !== -1) result.push(entry)
        }
        return result
    }

    function displayName(effectId) {
        return root.effect(effectId).name
    }

    function pathMap() {
        var result = ({})
        for (var index = 0; index < root.effects.length; index++)
            result[root.effects[index].id] = root.effects[index].path
        return result
    }
}

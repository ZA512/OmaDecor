import QtQuick

QtObject {
    id: root

    readonly property var styles: [
        {
            id: "raised-edge",
            name: "Raised Edge",
            description: "Thin top/right highlight with a thicker derived-dark bottom/left edge.",
            renderer: "native:omadecor-native",
            settingsSchema: {
                useThemeAccent: { type: "boolean", defaultValue: true },
                lightWidth: { type: "integer", minimum: 0, maximum: 20, defaultValue: 2 },
                darkWidth: { type: "integer", minimum: 0, maximum: 20, defaultValue: 5 },
                shadeFactor: { type: "number", minimum: 0, maximum: 1, defaultValue: 0.45 },
                inactiveOpacity: { type: "number", minimum: 0, maximum: 1, defaultValue: 0.55 },
                activeColor: { type: "color", defaultValue: "#47d7ff" },
                inactiveColor: { type: "color", defaultValue: "#64748b" }
            }
        }
    ]

    function style(styleId) {
        var requested = String(styleId || "")
        for (var index = 0; index < root.styles.length; index++) {
            if (root.styles[index].id === requested) return root.styles[index]
        }
        return null
    }

    function supports(styleId) {
        return root.style(styleId) !== null
    }

    function diagnostics() {
        var ids = []
        for (var index = 0; index < root.styles.length; index++) ids.push(root.styles[index].id)
        return { styleCount: ids.length, styleIds: ids }
    }
}

import QtQuick
import qs.Commons as Commons

QtObject {
    id: root

    readonly property string accentHex: root.colorHex(Commons.Color.accent, "#47d7ff")
    readonly property string foregroundHex: root.colorHex(Commons.Color.foreground, "#f2f4f8")
    readonly property string backgroundHex: root.colorHex(Commons.Color.background, "#111318")
    readonly property string mutedHex: root.colorHex(Commons.Color.muted, "#9ca3af")

    function colorHex(value, fallback) {
        var text = String(value || "").toLowerCase()
        if (/^#[0-9a-f]{6}$/.test(text)) return text
        if (/^#[0-9a-f]{8}$/.test(text)) return "#" + text.slice(3)
        return fallback
    }
}

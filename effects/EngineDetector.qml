import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var runtime: null
    property bool systemStateMentionsEngine: false
    property bool userStateMentionsEngine: false

    readonly property bool loaded: runtime ? runtime.effectsEngineLoaded : false
    readonly property bool installed: loaded || systemStateMentionsEngine || userStateMentionsEngine

    function inspect(text) {
        return String(text || "").toLowerCase().indexOf("hyprwindowshade") !== -1
    }

    FileView {
        path: "/var/cache/hyprpm/state.toml"
        watchChanges: true
        printErrors: false
        onLoaded: root.systemStateMentionsEngine = root.inspect(text())
        onLoadFailed: root.systemStateMentionsEngine = false
        onFileChanged: reload()
    }

    FileView {
        path: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share"))
            + "/hyprpm/state.toml"
        watchChanges: true
        printErrors: false
        onLoaded: root.userStateMentionsEngine = root.inspect(text())
        onLoadFailed: root.userStateMentionsEngine = false
        onFileChanged: reload()
    }
}

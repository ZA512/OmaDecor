import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var runtime: null
    property var config: null
    property var detector: null
    property var validatedEntries: []
    property string matrixError: ""

    readonly property string fingerprint: {
        if (!runtime || !runtime.effectsEngineLoaded) return ""
        return [
            runtime.hyprlandVersion,
            runtime.hyprlandCommit,
            runtime.hyprlandAbi,
            runtime.effectsEngineName,
            runtime.effectsEngineVersion,
            runtime.effectsEngineAuthor,
            runtime.effectsEngineDescription
        ].join("|")
    }
    readonly property bool overrideActive: fingerprint !== "" && config
        && config.effectsOverrideFingerprint === fingerprint
    readonly property bool validated: root.matchesValidatedEntry()
    readonly property string status: {
        if (!detector || !detector.installed) return "NOT_INSTALLED"
        if (!detector.loaded) return "INSTALLED_NOT_LOADED"
        if (matrixError !== "") return "ERROR"
        return validated ? "VALIDATED" : "UNTESTED"
    }
    readonly property bool effectsAllowed: status === "VALIDATED"
        || (status === "UNTESTED" && overrideActive)

    function matchesValidatedEntry() {
        if (!runtime || !runtime.effectsEngineLoaded) return false
        for (var index = 0; index < root.validatedEntries.length; index++) {
            var entry = root.validatedEntries[index] || {}
            if (String(entry.hyprlandCommit || "") !== runtime.hyprlandCommit) continue
            if (String(entry.hyprlandAbi || "") !== runtime.hyprlandAbi) continue
            if (String(entry.engineDescription || "") !== runtime.effectsEngineDescription) continue
            if (String(entry.engineVersion || "") !== runtime.effectsEngineVersion) continue
            return entry.status === "validated"
        }
        return false
    }

    function parseMatrix(rawText) {
        try {
            var value = JSON.parse(String(rawText || "{}"))
            if (Number(value.schemaVersion) !== 1 || !Array.isArray(value.validated))
                throw new Error("unsupported compatibility matrix")
            root.validatedEntries = value.validated
            root.matrixError = ""
        } catch (error) {
            root.validatedEntries = []
            root.matrixError = String(error)
        }
    }

    FileView {
        path: Qt.resolvedUrl("../compatibility/hyprwindowshade.json")
        watchChanges: true
        printErrors: false
        onLoaded: root.parseMatrix(text())
        onLoadFailed: root.matrixError = "Compatibility matrix unavailable"
        onFileChanged: reload()
    }
}

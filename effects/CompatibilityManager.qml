import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var runtime: null
    property var config: null
    property var detector: null
    property var validatedEntries: []
    property var effectEntries: []
    property string matrixError: ""
    property string observedStatus: ""
    property string observedFingerprint: ""

    signal notificationRequested(string title, string body)

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

    function entryMatchesFingerprint(entry) {
        if (!runtime || !entry) return false
        return String(entry.hyprlandCommit || "") === runtime.hyprlandCommit
            && String(entry.hyprlandAbi || "") === runtime.hyprlandAbi
            && String(entry.engineDescription || "") === runtime.effectsEngineDescription
            && String(entry.engineVersion || "") === runtime.effectsEngineVersion
    }

    function effectStatus(effectId, eventName) {
        if (effectId === "none" || effectId === "global") return "OK"
        for (var index = 0; index < root.effectEntries.length; index++) {
            var entry = root.effectEntries[index] || {}
            if (!root.entryMatchesFingerprint(entry)) continue
            if (String(entry.effect || "") !== String(effectId || "")) continue
            if (String(entry.event || "") !== String(eventName || "")) continue
            var value = String(entry.status || "UNTESTED").toUpperCase()
            return ["OK", "UNTESTED", "DEGRADED", "BROKEN"].indexOf(value) !== -1
                ? value : "UNTESTED"
        }
        return root.validated ? "OK" : "UNTESTED"
    }

    function parseMatrix(rawText) {
        try {
            var value = JSON.parse(String(rawText || "{}"))
            if (Number(value.schemaVersion) !== 1 || !Array.isArray(value.validated)
                    || !Array.isArray(value.effects))
                throw new Error("unsupported compatibility matrix")
            root.validatedEntries = value.validated
            root.effectEntries = value.effects
            root.matrixError = ""
        } catch (error) {
            root.validatedEntries = []
            root.effectEntries = []
            root.matrixError = String(error)
        }
    }

    function observeCompatibility() {
        var nextStatus = root.status
        var nextFingerprint = root.fingerprint
        if (root.observedStatus === "") {
            root.observedStatus = nextStatus
            root.observedFingerprint = nextFingerprint
            return
        }
        if (root.observedStatus === nextStatus && root.observedFingerprint === nextFingerprint) return

        if (nextStatus === "VALIDATED") {
            root.notificationRequested(
                "HyprWindowShade compatibility validated",
                "Window effects are available again.")
        } else if (nextStatus === "UNTESTED") {
            root.notificationRequested(
                "HyprWindowShade has changed",
                "Window effects were safely suspended until this fingerprint is approved.")
        } else if (nextStatus === "INSTALLED_NOT_LOADED") {
            root.notificationRequested(
                "HyprWindowShade is not loaded",
                "Decorations and HUD remain available.")
        }
        root.observedStatus = nextStatus
        root.observedFingerprint = nextFingerprint
    }

    onStatusChanged: Qt.callLater(root.observeCompatibility)
    onFingerprintChanged: Qt.callLater(root.observeCompatibility)

    FileView {
        path: Qt.resolvedUrl("../compatibility/hyprwindowshade.json")
        watchChanges: true
        printErrors: false
        onLoaded: root.parseMatrix(text())
        onLoadFailed: root.matrixError = "Compatibility matrix unavailable"
        onFileChanged: reload()
    }
}

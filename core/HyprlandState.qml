import QtQuick
import Quickshell
import Quickshell.Hyprland

Scope {
    id: root

    property bool debugEnabled: false
    property var snapshot: emptySnapshot()
    property var lastExternalSnapshot: emptySnapshot()
    property int revision: 0
    property string pendingEventReason: "refresh"
    property string activeRefreshReason: ""
    property int activeRefreshSerial: 0
    property int refreshSerial: 0

    signal samplePublished(var value, string source)

    function emptySnapshot() {
        return {
            address: "",
            stableId: "",
            appClass: "",
            applicationName: "",
            title: "",
            workspaceId: -1,
            monitorId: -1,
            x: 0,
            y: 0,
            width: 0,
            height: 0,
            fullscreen: false,
            floating: false,
            visible: false,
            observedAtMs: Date.now(),
            revision: root.revision
        }
    }

    function finiteNumber(value, fallback) {
        var parsed = Number(value)
        return isFinite(parsed) ? parsed : fallback
    }

    function resolvedToplevel() {
        if (Hyprland.activeToplevel) return Hyprland.activeToplevel

        var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (var index = 0; index < values.length; index++) {
            if (values[index] && values[index].activated === true)
                return values[index]
        }

        var best = null
        var bestFocusHistory = Number.POSITIVE_INFINITY
        for (var fallbackIndex = 0; fallbackIndex < values.length; fallbackIndex++) {
            var candidate = values[fallbackIndex]
            var raw = candidate ? (candidate.lastIpcObject || {}) : {}
            var focusHistory = Number(raw.focusHistoryID)
            if (isFinite(focusHistory) && focusHistory >= 0 && focusHistory < bestFocusHistory) {
                best = candidate
                bestFocusHistory = focusHistory
            }
        }
        return best
    }

    function normalize(toplevel) {
        if (!toplevel) return emptySnapshot()

        var raw = toplevel.lastIpcObject || {}
        var at = raw.at && raw.at.length >= 2 ? raw.at : []
        var size = raw.size && raw.size.length >= 2 ? raw.size : []
        var workspace = raw.workspace || {}
        var monitor = toplevel.monitor || null
        var address = String(raw.address || toplevel.address || "")
        var x = finiteNumber(at[0], 0)
        var y = finiteNumber(at[1], 0)
        var width = finiteNumber(size[0], 0)
        var height = finiteNumber(size[1], 0)
        var monitorId = raw.monitor !== undefined
            ? finiteNumber(raw.monitor, -1)
            : (monitor ? finiteNumber(monitor.id, -1) : -1)
        var workspaceId = workspace.id !== undefined
            ? finiteNumber(workspace.id, -1)
            : (toplevel.workspace ? finiteNumber(toplevel.workspace.id, -1) : -1)
        var fullscreenMode = finiteNumber(raw.fullscreen, 0)

        return {
            address: address,
            stableId: address,
            appClass: String(raw.class || raw.initialClass || ""),
            applicationName: String(raw.initialTitle || raw.class || raw.initialClass || ""),
            title: String(raw.title || ""),
            workspaceId: workspaceId,
            monitorId: monitorId,
            x: x,
            y: y,
            width: width,
            height: height,
            fullscreen: fullscreenMode > 0,
            floating: raw.floating === true,
            visible: address !== "" && width > 0 && height > 0,
            observedAtMs: Date.now(),
            revision: root.revision + 1
        }
    }

    function isOmaDecorClass(appClass) {
        var value = String(appClass || "").toLowerCase()
        return value === "omadecor" || value.indexOf("omadecor-") === 0
    }

    function applicationList() {
        var unusedRevision = root.revision
        var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
        var result = []
        var seen = []
        for (var index = 0; index < values.length; index++) {
            var toplevel = values[index]
            var raw = toplevel ? (toplevel.lastIpcObject || {}) : {}
            var appClass = String(raw.class || raw.initialClass || "").trim()
            var key = appClass.toLowerCase()
            if (appClass === "" || root.isOmaDecorClass(appClass) || seen.indexOf(key) !== -1) continue
            seen.push(key)
            var workspace = raw.workspace || {}
            result.push({
                appClass: appClass,
                name: String(raw.initialTitle || appClass),
                title: String(raw.title || ""),
                workspaceId: root.finiteNumber(workspace.id, -1),
                monitorId: root.finiteNumber(raw.monitor, -1)
            })
        }
        result.sort(function(left, right) {
            return String(left.name).toLowerCase().localeCompare(String(right.name).toLowerCase())
        })
        return result
    }

    function diagnostics() {
        var toplevel = resolvedToplevel()
        var raw = toplevel ? (toplevel.lastIpcObject || {}) : {}
        return {
            hasToplevel: !!toplevel,
            resolution: Hyprland.activeToplevel ? "activeToplevel"
                : (toplevel && toplevel.activated === true
                    ? "activated-list-entry"
                    : (toplevel ? "focus-history" : "none")),
            toplevelCount: Hyprland.toplevels ? Hyprland.toplevels.values.length : 0,
            runningApplicationCount: root.applicationList().length,
            lastExternalClass: root.lastExternalSnapshot.appClass,
            addressPresent: !!(toplevel && toplevel.address),
            rawKeys: Object.keys(raw),
            at: raw.at === undefined ? null : raw.at,
            size: raw.size === undefined ? null : raw.size,
            monitor: raw.monitor === undefined ? null : raw.monitor,
            workspace: raw.workspace && raw.workspace.id !== undefined
                ? raw.workspace.id : null,
            fullscreen: raw.fullscreen === undefined ? null : raw.fullscreen,
            floating: raw.floating === undefined ? null : raw.floating
        }
    }

    function publish(source) {
        root.revision += 1
        var next = normalize(resolvedToplevel())
        next.revision = root.revision
        root.snapshot = next
        if (next.visible && !root.isOmaDecorClass(next.appClass)) root.lastExternalSnapshot = next
        root.samplePublished(next, String(source || "unknown"))
    }

    function refresh(reason) {
        root.refreshSerial += 1
        var serial = root.refreshSerial
        var refreshReason = String(reason || "refresh")
        root.activeRefreshSerial = serial
        root.activeRefreshReason = refreshReason
        Hyprland.refreshToplevels()
        Qt.callLater(function() {
            if (root.activeRefreshSerial !== serial) return
            root.activeRefreshSerial = 0
            root.activeRefreshReason = ""
            root.publish("refresh:" + refreshReason + ":fallback")
        })
    }

    function shouldRefreshForEvent(name) {
        return [
            "activewindow", "activewindowv2", "openwindow", "closewindow",
            "workspace", "workspacev2", "focusedmon", "focusedmonv2",
            "fullscreen", "changefloatingmode", "movewindow", "movewindowv2",
            "monitoradded", "monitorremoved"
        ].indexOf(String(name || "")) !== -1
    }

    Timer {
        id: eventDebounce
        interval: 16
        repeat: false
        onTriggered: root.refresh(root.pendingEventReason)
    }

    Timer {
        id: startupRetry
        interval: 750
        repeat: false
        onTriggered: root.refresh("startup-retry")
    }

    Connections {
        target: Hyprland

        function onActiveToplevelChanged() {
            root.pendingEventReason = "active-toplevel"
            eventDebounce.restart()
        }

        function onRawEvent(event) {
            var name = String(event && event.name ? event.name : "")
            if (!root.shouldRefreshForEvent(name)) return
            root.pendingEventReason = "event:" + name
            eventDebounce.restart()
        }
    }

    Connections {
        target: root.resolvedToplevel()
        ignoreUnknownSignals: true

        function onLastIpcObjectChanged() {
            var refreshReason = root.activeRefreshReason
            root.activeRefreshSerial = 0
            root.activeRefreshReason = ""
            root.publish(refreshReason ? "refresh:" + refreshReason : "native-object")
        }
    }

    Component.onCompleted: {
        root.refresh("state-start")
        startupRetry.start()
    }
}

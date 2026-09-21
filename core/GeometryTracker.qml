import QtQuick
import Quickshell

Scope {
    id: root

    property var source: null
    property bool enabled: true
    property bool debugEnabled: false
    property var excludedClasses: []
    property int sentinelHz: 16
    property int unstableHz: 30
    property int stabilityWindowMs: 120
    property int fadeOutMs: 80
    property int fadeInMs: 150
    property int minimumStableSamples: 2
    property int maxTraceEntries: 200

    property string state: "NO_WINDOW"
    property bool shown: false
    property var candidateSnapshot: ({})
    property var displaySnapshot: ({})
    property int stableSamples: 0
    property double lastGeometryChangeMs: 0
    property int sampleCount: 0
    property int transitionCount: 0
    property var trace: []

    signal stateTransition(string previousState, string nextState, string reason)

    function eligible(snapshot) {
        if (!snapshot || snapshot.visible !== true || snapshot.fullscreen === true) return false
        var appClass = String(snapshot.appClass || "").toLowerCase()
        for (var index = 0; index < root.excludedClasses.length; index++) {
            if (String(root.excludedClasses[index] || "").toLowerCase() === appClass) return false
        }
        return true
    }

    function sameGeometry(left, right) {
        if (!left || !right) return false
        return left.address === right.address
            && left.monitorId === right.monitorId
            && left.workspaceId === right.workspaceId
            && left.x === right.x
            && left.y === right.y
            && left.width === right.width
            && left.height === right.height
            && left.fullscreen === right.fullscreen
            && left.floating === right.floating
    }

    function geometrySummary(snapshot) {
        if (!snapshot || snapshot.visible !== true) return null
        return {
            x: snapshot.x,
            y: snapshot.y,
            width: snapshot.width,
            height: snapshot.height,
            monitorId: snapshot.monitorId,
            workspaceId: snapshot.workspaceId,
            fullscreen: snapshot.fullscreen,
            floating: snapshot.floating
        }
    }

    function recordExternal(eventName, details) {
        if (!root.debugEnabled) return
        var next = root.trace.slice()
        next.push({
            atMs: Date.now(),
            event: String(eventName),
            state: root.state,
            details: details || {}
        })
        if (next.length > root.maxTraceEntries)
            next = next.slice(next.length - root.maxTraceEntries)
        root.trace = next
    }

    function transition(nextState, reason) {
        if (root.state === nextState) return
        var previous = root.state
        root.state = nextState
        root.transitionCount += 1
        root.recordExternal("state-transition", {
            from: previous,
            to: nextState,
            reason: String(reason || "")
        })
        root.stateTransition(previous, nextState, String(reason || ""))
    }

    function clearTarget(reason) {
        stabilityTimer.stop()
        settlingTimer.stop()
        root.candidateSnapshot = ({})
        root.stableSamples = 0
        root.shown = false
        root.transition("NO_WINDOW", reason)
    }

    function consider(snapshot, sourceName) {
        root.sampleCount += 1

        if (!root.enabled || !root.eligible(snapshot)) {
            var reason = snapshot && snapshot.fullscreen ? "fullscreen"
                : (snapshot && snapshot.visible ? "application-excluded" : "no-window")
            root.clearTarget(reason)
            return
        }

        if (!root.sameGeometry(root.candidateSnapshot, snapshot)) {
            root.candidateSnapshot = snapshot
            root.stableSamples = 1
            root.lastGeometryChangeMs = Date.now()
            root.shown = false
            root.transition("HIDDEN", "geometry-change")
            settlingTimer.restart()
            stabilityTimer.interval = root.stabilityWindowMs
            stabilityTimer.restart()
            root.recordExternal("geometry-change", {
                source: String(sourceName || "snapshot"),
                geometry: root.geometrySummary(snapshot)
            })
            return
        }

        root.candidateSnapshot = snapshot
        root.stableSamples += 1

        if (root.state === "STABLE")
            root.displaySnapshot = snapshot
    }

    function tryStabilize() {
        if (!root.enabled || !root.eligible(root.candidateSnapshot)) return

        var elapsed = Date.now() - root.lastGeometryChangeMs
        if (root.stableSamples < root.minimumStableSamples || elapsed < root.stabilityWindowMs) {
            stabilityTimer.interval = Math.max(10, root.stabilityWindowMs - elapsed)
            stabilityTimer.restart()
            return
        }

        root.displaySnapshot = root.candidateSnapshot
        root.transition("STABLE", "stability-window")
        root.shown = true
        root.recordExternal("geometry-stable", {
            samples: root.stableSamples,
            stableForMs: elapsed,
            geometry: root.geometrySummary(root.displaySnapshot)
        })
    }

    Timer {
        id: sampleTimer
        interval: Math.max(1, Math.round(1000 / (
            root.state === "HIDDEN" || root.state === "SETTLING"
                ? root.unstableHz : root.sentinelHz)))
        repeat: true
        running: root.enabled && root.source !== null && root.state !== "NO_WINDOW"
        triggeredOnStart: true
        onTriggered: if (root.source) root.source.refresh("sentinel")
    }

    Timer {
        id: settlingTimer
        interval: root.fadeOutMs
        repeat: false
        onTriggered: if (root.state === "HIDDEN") root.transition("SETTLING", "fade-out")
    }

    Timer {
        id: stabilityTimer
        interval: root.stabilityWindowMs
        repeat: false
        onTriggered: root.tryStabilize()
    }

    Connections {
        target: root.source
        ignoreUnknownSignals: true

        function onSamplePublished(value, sourceName) {
            root.consider(value, sourceName)
        }
    }

    onEnabledChanged: {
        if (!root.enabled) root.clearTarget("disabled")
        else if (root.source) root.source.refresh("enabled")
    }

    onExcludedClassesChanged: {
        if (root.enabled && root.source) root.source.refresh("exclusions-changed")
    }

    onSentinelHzChanged: root.recordExternal("sentinel-rate", { hz: root.sentinelHz })
}

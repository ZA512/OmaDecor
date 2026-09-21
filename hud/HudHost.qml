pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons

Scope {
    id: root

    property bool enabled: false
    property var tracker: null
    property var metrics: null
    property var monitors: []

    readonly property var snapshot: root.tracker ? root.tracker.displaySnapshot : ({})
    readonly property bool shown: root.tracker ? root.tracker.shown : false
    readonly property int surfaceCount: root.enabled ? Quickshell.screens.length : 0

    function monitorFor(monitorId) {
        for (var index = 0; index < root.monitors.length; index++) {
            if (Number(root.monitors[index].id) === Number(monitorId)) return root.monitors[index]
        }
        return null
    }

    function diagnostics() {
        return {
            enabled: root.enabled,
            shown: root.shown,
            surfaceCount: root.surfaceCount,
            targetMonitorId: root.snapshot ? Number(root.snapshot.monitorId) : -1,
            targetAddress: root.snapshot ? String(root.snapshot.address || "") : ""
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: hudWindow

            required property var modelData
            readonly property var targetMonitor: root.monitorFor(root.snapshot.monitorId)
            readonly property bool targetScreen: !!targetMonitor && targetMonitor.name === modelData.name
            readonly property real targetX: Number(root.snapshot.x || 0) - Number(targetMonitor ? targetMonitor.x : 0)
            readonly property real targetY: Number(root.snapshot.y || 0) - Number(targetMonitor ? targetMonitor.y : 0)
            readonly property real targetWidth: Number(root.snapshot.width || 0)
            readonly property real targetHeight: Number(root.snapshot.height || 0)

            screen: modelData
            visible: root.enabled && hudWindow.targetScreen
                && root.snapshot.visible === true && root.snapshot.fullscreen !== true
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: false
            mask: Region {}
            anchors { top: true; right: true; bottom: true; left: true }

            WlrLayershell.namespace: "omadecor-hud"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Item {
                id: canvas
                anchors.fill: parent
                opacity: root.shown ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.shown && root.tracker ? root.tracker.fadeInMs
                            : (root.tracker ? root.tracker.fadeOutMs : 80)
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    id: identityCard
                    width: Math.min(360, Math.max(210, identityColumn.implicitWidth + 24))
                    height: identityColumn.implicitHeight + 18
                    radius: Commons.Style.cornerRadius
                    color: Commons.Util.alpha(Commons.Color.background, 0.92)
                    border.color: Commons.Color.popups.border
                    border.width: 1
                    x: Math.max(6, Math.min(hudWindow.width - width - 6, hudWindow.targetX))
                    y: hudWindow.targetY >= height + 8 ? hudWindow.targetY - height - 6
                        : Math.max(6, hudWindow.targetY + 8)

                    Column {
                        id: identityColumn
                        anchors.centerIn: parent
                        width: parent.width - 24
                        spacing: 2

                        Text {
                            width: parent.width
                            text: String(root.snapshot.applicationName || root.snapshot.appClass || "Application")
                            color: Commons.Color.accent
                            font.pixelSize: 12
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: String(root.snapshot.title || "Untitled window")
                            color: Commons.Color.foreground
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Text {
                            text: "WS " + String(root.snapshot.workspaceId)
                            color: Commons.Color.muted
                            font.pixelSize: 10
                        }
                    }
                }

                Rectangle {
                    id: metricsCard
                    width: 300
                    height: 42
                    radius: Commons.Style.cornerRadius
                    color: Commons.Util.alpha(Commons.Color.background, 0.92)
                    border.color: Commons.Color.popups.border
                    border.width: 1
                    x: Math.max(6, Math.min(hudWindow.width - width - 6,
                        hudWindow.targetX + hudWindow.targetWidth - width))
                    y: hudWindow.targetY + hudWindow.targetHeight + height + 6 <= hudWindow.height
                        ? hudWindow.targetY + hudWindow.targetHeight + 6
                        : Math.max(6, hudWindow.targetY + hudWindow.targetHeight - height - 8)

                    Row {
                        anchors.centerIn: parent
                        spacing: 15

                        Text {
                            text: root.metrics && root.metrics.cpuAvailable
                                ? "CPU " + Math.round(root.metrics.cpuPercent) + "%" : "CPU —"
                            color: Commons.Color.foreground
                            font.pixelSize: 11
                        }
                        Text {
                            text: root.metrics && root.metrics.memoryAvailable
                                ? "RAM " + Math.round(root.metrics.memoryPercent) + "%" : "RAM —"
                            color: Commons.Color.foreground
                            font.pixelSize: 11
                        }
                        Text {
                            text: root.metrics && root.metrics.networkAvailable
                                ? "↓ " + root.metrics.humanRate(root.metrics.networkReceiveBytesPerSecond)
                                    + "  ↑ " + root.metrics.humanRate(root.metrics.networkTransmitBytesPerSecond)
                                : "NET —"
                            color: Commons.Color.foreground
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}

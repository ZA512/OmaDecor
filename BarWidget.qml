import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.BarWidget {
    id: root

    moduleName: "omadecor"

    readonly property var omaService: bar && bar.shell
        ? bar.shell.serviceFor("omadecor") : null
    readonly property bool degraded: !omaService
        || !omaService.configHealthy
        || (omaService.decorationsEnabled && !omaService.nativeDecorationLoaded)
    readonly property string moduleSummary: omaService
        ? "Decorations " + (omaService.decorationsEnabled ? "on" : "off")
            + " · HUD " + (omaService.hudEnabled ? "on" : "off")
            + " · Effects " + (omaService.effectsEnabled ? "on" : "off")
        : "Service unavailable"

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    Ui.WidgetButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        text: "OD"
        fontSize: Commons.Style.font.bodySmall
        horizontalMargin: 7
        active: root.degraded
        activeColor: root.bar ? root.bar.urgent : Commons.Color.urgent
        tooltipText: "OmaDecor — " + root.moduleSummary

        onPressed: function(buttonCode) {
            if (!root.bar || !root.bar.shell) return
            if (buttonCode === Qt.MiddleButton) {
                if (root.omaService) root.omaService.refresh()
            } else if (buttonCode === Qt.RightButton) {
                root.bar.shell.summon("omadecor", JSON.stringify({ page: "applications" }))
            } else {
                root.bar.shell.toggle("omadecor", "{}")
            }
        }
    }
}

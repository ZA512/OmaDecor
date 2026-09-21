pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons

Item {
    id: root

    property var shell: null
    property var manifest: null
    property var service: null
    property bool opened: false
    property bool serviceIdentityMatched: false
    property string payloadError: ""
    property string currentPage: "overview"
    property bool draftDirty: false
    property string actionMessage: ""
    readonly property string effectsInstallCommands: "hyprpm add https://github.com/ManofJELLO/HyprWindowShade\n"
        + "hyprpm enable HyprWindowShade\n"
        + "hyprpm reload"

    readonly property color panelColor: Commons.Color.popups.background
    readonly property color foregroundColor: Commons.Color.popups.text
    readonly property color mutedColor: Commons.Color.muted
    readonly property color accentColor: Commons.Color.accent

    function resolveServiceIdentity() {
        if (!root.shell || !root.service || !root.manifest) return false
        if (typeof root.shell.serviceFor !== "function") return false
        return root.shell.serviceFor(String(root.manifest.id || "omadecor")) === root.service
    }

    function syncDraft() {
        if (!root.service) return
        lightWidthField.text = String(root.service.lightWidth)
        darkWidthField.text = String(root.service.darkWidth)
        shadeField.text = String(Math.round(root.service.shadeFactor * 100))
        opacityField.text = String(Math.round(root.service.inactiveOpacity * 100))
        activeColorField.text = root.service.activeColor
        inactiveColorField.text = root.service.inactiveColor
        root.draftDirty = false
    }

    function open(payloadJson) {
        var payload = {}
        root.payloadError = ""
        try {
            payload = JSON.parse(payloadJson || "{}") || {}
        } catch (error) {
            root.payloadError = "Invalid JSON payload"
        }

        root.serviceIdentityMatched = root.resolveServiceIdentity()
        if (root.service) {
            if (payload.debug !== undefined) root.service.setDebug(payload.debug)
            root.service.recordPanelOpened(payloadJson, root.serviceIdentityMatched)
        }
        root.currentPage = payload.page === "applications" || payload.page === "decorations"
            || payload.page === "effects"
            ? payload.page : "overview"
        root.actionMessage = ""
        root.syncDraft()
        root.opened = true
    }

    function close() {
        if (root.service) root.service.recordPanelClosed()
        root.opened = false
    }

    function dismiss() {
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide((root.manifest && root.manifest.id) || "omadecor")
        else
            root.close()
    }

    function applyDecorationDraft() {
        if (!root.service) return
        root.service.setDecorationSettings(JSON.stringify({
            lightWidth: Number(lightWidthField.text),
            darkWidth: Number(darkWidthField.text),
            shadeFactor: Number(shadeField.text) / 100,
            inactiveOpacity: Number(opacityField.text) / 100,
            activeColor: activeColorField.text,
            inactiveColor: inactiveColorField.text
        }))
        root.actionMessage = "Decoration settings applied"
        root.syncDraft()
    }

    function toggleApplication(entry, key) {
        if (!root.service || !entry) return
        var values = {
            disableDecorations: entry.disableDecorations === true,
            disableHud: entry.disableHud === true,
            disableEffects: entry.disableEffects === true
        }
        values[key] = !values[key]
        root.service.setApplicationExclusions(entry.appClass, values)
    }

    function effectsStatusText() {
        if (!root.service) return "Effects service unavailable"
        var status = root.service.effectsCompatibilityStatus
        if (status === "NOT_INSTALLED")
            return "Effects engine not installed. Decorations and HUD continue to work normally."
        if (status === "INSTALLED_NOT_LOADED")
            return "HyprWindowShade is installed but not loaded. Run hyprpm reload, then check again."
        if (status === "VALIDATED") return "HyprWindowShade is validated for this Hyprland ABI."
        if (status === "UNTESTED" && root.service.effectsOverrideActive)
            return "Untested engine fingerprint — user override active."
        if (status === "UNTESTED")
            return "HyprWindowShade has not been validated with this exact Hyprland ABI. Effects are safely suspended."
        return "Window effects are unavailable: " + (root.service.effectsError || status)
    }

    component ActionButton: Rectangle {
        id: actionButton

        required property string label
        property bool selected: false
        property int buttonWidth: 126
        signal clicked()

        width: buttonWidth
        height: 34
        radius: 7
        color: selected ? root.accentColor : Commons.Color.background
        border.color: selected ? root.accentColor : Commons.Color.popups.border
        opacity: enabled ? 1 : 0.5

        Text {
            anchors.centerIn: parent
            text: actionButton.label
            color: actionButton.selected ? Commons.Color.background : root.foregroundColor
            font.pixelSize: 12
            font.bold: actionButton.selected
        }

        MouseArea {
            anchors.fill: parent
            enabled: actionButton.enabled
            onClicked: actionButton.clicked()
        }
    }

    component TogglePill: Rectangle {
        id: togglePill

        required property string label
        required property bool checked
        signal toggled()

        width: Math.max(72, toggleLabel.implicitWidth + 24)
        height: 28
        radius: 14
        color: checked ? root.accentColor : Commons.Color.background
        border.color: checked ? root.accentColor : Commons.Color.popups.border

        Text {
            id: toggleLabel
            anchors.centerIn: parent
            text: togglePill.label + " " + (togglePill.checked ? "ON" : "OFF")
            color: togglePill.checked ? Commons.Color.background : root.mutedColor
            font.pixelSize: 11
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            onClicked: togglePill.toggled()
        }
    }

    component LabeledField: Column {
        id: field

        required property string label
        property alias text: input.text
        property int fieldWidth: 150
        signal edited()

        spacing: 4

        Text {
            text: field.label
            color: root.mutedColor
            font.pixelSize: 11
        }

        Rectangle {
            width: field.fieldWidth
            height: 34
            radius: 6
            color: Commons.Color.background
            border.color: input.activeFocus ? root.accentColor : Commons.Color.popups.border

            TextInput {
                id: input
                anchors.fill: parent
                anchors.margins: 9
                color: root.foregroundColor
                selectionColor: root.accentColor
                font.pixelSize: 13
                clip: true
                onTextEdited: field.edited()
            }
        }
    }

    component ModuleRow: Rectangle {
        id: moduleRow

        required property string title
        required property string detail
        required property bool active
        property bool available: true
        signal toggleRequested(bool nextValue)

        width: parent ? parent.width : 0
        height: 70
        radius: 9
        color: Commons.Color.background
        border.color: moduleRow.active ? root.accentColor : Commons.Color.popups.border

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: moduleToggle.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Text { text: moduleRow.title; color: root.foregroundColor; font.pixelSize: 15; font.bold: true }
            Text {
                width: parent.width
                text: moduleRow.detail
                color: moduleRow.available ? root.mutedColor : Commons.Color.urgent
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }

        TogglePill {
            id: moduleToggle
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            label: ""
            checked: moduleRow.active
            onToggled: moduleRow.toggleRequested(!moduleRow.active)
        }
    }

    component EffectRow: Rectangle {
        id: effectRow

        required property string eventName
        required property string title
        readonly property string effectId: root.service
            ? String(root.service.effectsEvents[eventName] || "none") : "none"

        width: effectsGrid.width > 0 ? (effectsGrid.width - 8) / 2 : 0
        height: 42
        radius: 7
        color: Commons.Color.background
        border.color: Commons.Color.popups.border

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: effectRow.title
            color: root.foregroundColor
            font.pixelSize: 12
            font.bold: true
        }

        ActionButton {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            label: root.service ? root.service.effectDisplayName(effectRow.effectId) : "None"
            buttonWidth: 118
            selected: effectRow.effectId !== "none"
            onClicked: if (root.service) root.actionMessage = root.service.cycleEffect(effectRow.eventName)
        }
    }

    PanelWindow {
        id: window
        visible: root.opened
        anchors { top: true; right: true; bottom: true; left: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        focusable: true

        WlrLayershell.namespace: "omadecor-panel"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.46)
            MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(760, window.width - 40)
            height: Math.min(760, window.height - 40)
            radius: 12
            color: root.panelColor
            border.color: Commons.Color.popups.border

            MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }

            Item {
                anchors.fill: parent
                anchors.margins: 24
                focus: true
                Keys.onEscapePressed: root.dismiss()

                Column {
                    anchors.fill: parent
                    spacing: 12

                    Row {
                        width: parent.width
                        spacing: 10

                        Text {
                            width: parent.width - navButtons.width - 10
                            text: "OmaDecor"
                            color: root.foregroundColor
                            font.pixelSize: 24
                            font.bold: true
                        }

                        Row {
                            id: navButtons
                            spacing: 6
                            ActionButton { label: "Overview"; buttonWidth: 86; selected: root.currentPage === "overview"; onClicked: root.currentPage = "overview" }
                            ActionButton { label: "Decoration"; buttonWidth: 92; selected: root.currentPage === "decorations"; onClicked: { root.currentPage = "decorations"; root.syncDraft() } }
                            ActionButton { label: "Effects"; buttonWidth: 78; selected: root.currentPage === "effects"; onClicked: { root.currentPage = "effects"; if (root.service) root.service.refresh() } }
                            ActionButton { label: "Applications"; buttonWidth: 98; selected: root.currentPage === "applications"; onClicked: root.currentPage = "applications" }
                        }
                    }

                    Text {
                        width: parent.width
                        text: !root.service ? "Service unavailable"
                            : (!root.serviceIdentityMatched ? "Service identity mismatch"
                                : (root.service.configHealthy ? "Configuration loaded" : root.service.configError))
                        color: root.service && root.serviceIdentityMatched && root.service.configHealthy
                            ? root.accentColor : Commons.Color.urgent
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }

                    Item {
                        width: parent.width
                        height: parent.height - 112

                        Column {
                            anchors.fill: parent
                            spacing: 10
                            visible: root.currentPage === "overview"

                            ModuleRow {
                                title: "Window Decorations"
                                active: root.service ? root.service.decorationsEnabled : false
                                available: root.service ? root.service.nativeDecorationLoaded : false
                                detail: !root.service ? "Unavailable" : (root.service.nativeDecorationLoaded
                                    ? "Raised Edge · native Hyprland · " + root.service.nativeApplyState
                                    : "Native plugin not loaded · stock border restored")
                                onToggleRequested: function(nextValue) { if (root.service) root.service.setModuleEnabled("decorations", nextValue) }
                            }
                            ModuleRow {
                                title: "Window HUD"
                                active: root.service ? root.service.hudEnabled : false
                                detail: "Active-window identity and system metrics · hides while moving"
                                onToggleRequested: function(nextValue) { if (root.service) root.service.setModuleEnabled("hud", nextValue) }
                            }
                            ModuleRow {
                                title: "Window Effects"
                                active: root.service ? root.service.effectsEnabled : false
                                available: root.service ? root.service.effectsEngineInstalled : false
                                detail: root.service ? "HyprWindowShade · " + root.service.effectsCompatibilityStatus
                                    + (root.service.effectsPending ? " · changes pending" : "") : "Unavailable"
                                onToggleRequested: function(nextValue) { if (root.service) root.service.setModuleEnabled("effects", nextValue) }
                            }
                            Text {
                                width: parent.width
                                text: root.service ? "Accent " + root.service.themeAccent + " · native "
                                    + root.service.nativeApplyState + " · HUD " + root.service.trackerState : ""
                                color: root.mutedColor
                                font.pixelSize: 12
                            }
                        }

                        Column {
                            anchors.fill: parent
                            spacing: 9
                            visible: root.currentPage === "effects"

                            Row {
                                width: parent.width
                                spacing: 10
                                Text {
                                    width: parent.width - effectsToggle.width - 10
                                    text: "Window Effects"
                                    color: root.foregroundColor
                                    font.pixelSize: 18
                                    font.bold: true
                                }
                                TogglePill {
                                    id: effectsToggle
                                    label: "Effects"
                                    checked: root.service ? root.service.effectsEnabled : false
                                    onToggled: if (root.service) root.service.setModuleEnabled("effects", !checked)
                                }
                            }

                            Text {
                                width: parent.width
                                text: root.effectsStatusText()
                                color: root.service && root.service.effectsAllowed
                                    ? root.accentColor : Commons.Color.urgent
                                font.pixelSize: 12
                                wrapMode: Text.Wrap
                            }

                            Rectangle {
                                width: parent.width
                                height: installColumn.implicitHeight + 16
                                radius: 7
                                color: Commons.Color.background
                                border.color: Commons.Color.popups.border
                                visible: root.service && !root.service.effectsEngineLoaded

                                Column {
                                    id: installColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 8
                                    spacing: 5
                                    Text { text: "Window effects powered by HyprWindowShade · ManofJELLO · external MIT project"; color: root.mutedColor; font.pixelSize: 11 }
                                    Text { text: root.effectsInstallCommands; color: root.foregroundColor; font.pixelSize: 11; font.family: "monospace" }
                                }
                            }

                            Grid {
                                id: effectsGrid
                                width: parent.width
                                columns: 2
                                columnSpacing: 8
                                rowSpacing: 6

                                EffectRow { eventName: "open"; title: "Open" }
                                EffectRow { eventName: "close"; title: "Close" }
                                EffectRow { eventName: "move"; title: "Move" }
                                EffectRow { eventName: "resize"; title: "Resize" }
                                EffectRow { eventName: "workspace"; title: "Workspace" }
                                EffectRow { eventName: "focus"; title: "Focus" }
                                EffectRow { eventName: "unfocus"; title: "Unfocus" }
                                EffectRow { eventName: "urgent"; title: "Urgent" }
                                EffectRow { eventName: "float"; title: "Float" }
                                EffectRow { eventName: "tile"; title: "Tile" }
                                EffectRow { eventName: "fullscreenEnter"; title: "Fullscreen in" }
                                EffectRow { eventName: "fullscreenExit"; title: "Fullscreen out" }
                            }

                            Row {
                                spacing: 8
                                ActionButton {
                                    label: "Copy install"
                                    buttonWidth: 105
                                    visible: root.service && !root.service.effectsEngineLoaded
                                    onClicked: {
                                        Quickshell.execDetached(["/usr/bin/wl-copy", root.effectsInstallCommands])
                                        root.actionMessage = "Installation commands copied"
                                    }
                                }
                                ActionButton {
                                    label: "Check again"
                                    buttonWidth: 105
                                    onClicked: if (root.service) root.actionMessage = root.service.refresh()
                                }
                                ActionButton {
                                    label: "Test anyway"
                                    buttonWidth: 105
                                    visible: root.service && root.service.effectsCompatibilityStatus === "UNTESTED"
                                        && !root.service.effectsOverrideActive
                                    onClicked: if (root.service) root.actionMessage = root.service.testEffectsAnyway()
                                }
                                ActionButton {
                                    label: "Apply"
                                    buttonWidth: 90
                                    selected: root.service ? root.service.effectsPending : false
                                    enabled: root.service ? root.service.effectsPending : false
                                    onClicked: if (root.service) root.actionMessage = root.service.applyEffects()
                                }
                            }

                            Text {
                                width: parent.width
                                text: root.service ? (root.service.effectsPending ? "Changes pending"
                                    : "State: " + root.service.effectsApplyState)
                                    + (root.service.effectsError ? " · " + root.service.effectsError : "") : ""
                                color: root.service && root.service.effectsError === ""
                                    ? root.mutedColor : Commons.Color.urgent
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }
                        }

                        Column {
                            anchors.fill: parent
                            spacing: 13
                            visible: root.currentPage === "decorations"

                            Text { text: "Raised Edge"; color: root.foregroundColor; font.pixelSize: 18; font.bold: true }
                            Text {
                                width: parent.width
                                text: "Native renderer. Widths are logical pixels and Hyprland scales them per monitor."
                                color: root.mutedColor
                                font.pixelSize: 12
                                wrapMode: Text.Wrap
                            }

                            Row {
                                spacing: 10
                                TogglePill {
                                    label: "Theme accent"
                                    checked: root.service ? root.service.useThemeAccent : true
                                    onToggled: if (root.service) root.service.setDecorationSettings(JSON.stringify({ useThemeAccent: !checked }))
                                }
                                Rectangle { width: 34; height: 28; radius: 6; color: root.service ? root.service.themeAccent : root.accentColor; border.color: root.foregroundColor }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: root.service ? root.service.themeAccent : ""; color: root.mutedColor; font.pixelSize: 12 }
                            }

                            Row {
                                spacing: 12
                                LabeledField { id: lightWidthField; label: "Top/right width (0–20)"; onEdited: root.draftDirty = true }
                                LabeledField { id: darkWidthField; label: "Bottom/left width (0–20)"; onEdited: root.draftDirty = true }
                                LabeledField { id: shadeField; label: "Darkening factor (%)"; onEdited: root.draftDirty = true }
                                LabeledField { id: opacityField; label: "Inactive opacity (%)"; onEdited: root.draftDirty = true }
                            }

                            Row {
                                spacing: 12
                                LabeledField { id: activeColorField; label: "Manual active color"; fieldWidth: 210; onEdited: root.draftDirty = true }
                                LabeledField { id: inactiveColorField; label: "Manual inactive color"; fieldWidth: 210; onEdited: root.draftDirty = true }
                            }

                            Text {
                                text: root.draftDirty ? "Changes pending" : root.actionMessage
                                color: root.draftDirty ? Commons.Color.urgent : root.accentColor
                                font.pixelSize: 12
                            }

                            Row {
                                spacing: 10
                                ActionButton { label: "Apply"; selected: root.draftDirty; enabled: root.draftDirty; onClicked: root.applyDecorationDraft() }
                                ActionButton { label: "Discard"; enabled: root.draftDirty; onClicked: root.syncDraft() }
                            }
                        }

                        Column {
                            anchors.fill: parent
                            spacing: 10
                            visible: root.currentPage === "applications"

                            Row {
                                width: parent.width
                                spacing: 10
                                Text { width: parent.width - addLastButton.width - 10; text: "Application exclusions"; color: root.foregroundColor; font.pixelSize: 18; font.bold: true }
                                ActionButton {
                                    id: addLastButton
                                    label: "Add last active"
                                    buttonWidth: 130
                                    onClicked: root.actionMessage = root.service ? root.service.addLastActiveApplication() : "unavailable"
                                }
                            }

                            Text {
                                width: parent.width
                                text: "Tracked applications. Exclusions are independent; decoration exclusions are applied natively by exact class."
                                color: root.mutedColor
                                font.pixelSize: 12
                                wrapMode: Text.Wrap
                            }

                            Text { text: "Configured"; color: root.foregroundColor; font.pixelSize: 13; font.bold: true }
                            Flickable {
                                width: parent.width
                                height: Math.min(174, Math.max(30, configuredColumn.height))
                                contentWidth: width
                                contentHeight: configuredColumn.height
                                clip: true

                                Column {
                                    id: configuredColumn
                                    width: parent.width
                                    spacing: 6
                                    Repeater {
                                        model: root.service ? root.service.applications : []
                                        delegate: Rectangle {
                                            id: configuredApp
                                            required property var modelData
                                            width: parent ? parent.width : 0
                                            height: 54
                                            radius: 7
                                            color: Commons.Color.background
                                            border.color: Commons.Color.popups.border

                                            Column {
                                                anchors.left: parent.left
                                                anchors.leftMargin: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 250
                                                spacing: 3
                                                Text { text: configuredApp.modelData.name; color: root.foregroundColor; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight; width: parent.width }
                                                Text { text: configuredApp.modelData.appClass; color: root.mutedColor; font.pixelSize: 10; elide: Text.ElideRight; width: parent.width }
                                            }

                                            Row {
                                                anchors.right: parent.right
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 6
                                                TogglePill { label: "Decor"; checked: configuredApp.modelData.disableDecorations === true; onToggled: root.toggleApplication(configuredApp.modelData, "disableDecorations") }
                                                TogglePill { label: "HUD"; checked: configuredApp.modelData.disableHud === true; onToggled: root.toggleApplication(configuredApp.modelData, "disableHud") }
                                                TogglePill { label: "FX"; checked: configuredApp.modelData.disableEffects === true; onToggled: root.toggleApplication(configuredApp.modelData, "disableEffects") }
                                                ActionButton { label: "Remove"; buttonWidth: 70; onClicked: if (root.service) root.service.removeApplication(configuredApp.modelData.appClass) }
                                            }
                                        }
                                    }
                                    Text { visible: !root.service || root.service.applications.length === 0; text: "No application rule configured."; color: root.mutedColor; font.pixelSize: 12 }
                                }
                            }

                            Text { text: "Running applications"; color: root.foregroundColor; font.pixelSize: 13; font.bold: true }
                            Flickable {
                                width: parent.width
                                height: Math.max(90, parent.height - y)
                                contentWidth: width
                                contentHeight: runningColumn.height
                                clip: true

                                Column {
                                    id: runningColumn
                                    width: parent.width
                                    spacing: 5
                                    Repeater {
                                        model: root.service ? root.service.runningApplications : []
                                        delegate: Rectangle {
                                            id: runningApp
                                            required property var modelData
                                            width: parent ? parent.width : 0
                                            height: 48
                                            radius: 7
                                            color: Commons.Color.background

                                            Column {
                                                anchors.left: parent.left
                                                anchors.leftMargin: 10
                                                anchors.right: addButton.left
                                                anchors.rightMargin: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                Text { width: parent.width; text: runningApp.modelData.name + " · workspace " + runningApp.modelData.workspaceId; color: root.foregroundColor; font.pixelSize: 12; elide: Text.ElideRight }
                                                Text { width: parent.width; text: runningApp.modelData.appClass + " · " + runningApp.modelData.title; color: root.mutedColor; font.pixelSize: 10; elide: Text.ElideRight }
                                            }

                                            ActionButton {
                                                id: addButton
                                                anchors.right: parent.right
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                label: "Exclude decor"
                                                buttonWidth: 108
                                                onClicked: if (root.service) root.service.addApplication({
                                                    appClass: runningApp.modelData.appClass,
                                                    name: runningApp.modelData.name,
                                                    title: runningApp.modelData.title,
                                                    disableDecorations: true,
                                                    disableHud: false,
                                                    disableEffects: false
                                                })
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

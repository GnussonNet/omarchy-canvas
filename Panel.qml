pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui as Ui

Ui.Panel {
    id: root
    moduleName: "canvas.assignments"
    manageIpc: false
    property var anchorItem: null
    property var hostWidget: null
    property bool editingSettings: false
    readonly property bool showSettings: editingSettings
    readonly property int daysAhead: hostWidget ? hostWidget.daysAhead : 7
    function openSettings() {
        editingSettings = true
        if (hostWidget) hostWidget.cancelRefresh()
    }
    onOpenedChanged: {
        if (!opened && settingsLoader.item) {
            settingsLoader.item.clearSecret()
            if (!settingsLoader.item.saving) editingSettings = false
        }
    }
    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.hostWidget || root, direction)
        return false
    }
    Ui.KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: root.showSettings ? (settingsLoader.item as Item) : keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(430))
        contentHeight: panel.fittedContentHeight(Style.space(500))
        Ui.PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            blocked: root.showSettings
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction) }
            Column {
                id: header
                visible: !root.showSettings
                width: parent.width
                spacing: Style.space(8)
                Row {
                    width: parent.width
                    Text {
                        width: parent.width - settingsButton.width
                        height: settingsButton.height
                        verticalAlignment: Text.AlignVCenter
                        text: "Canvas · Next " + root.daysAhead + (root.daysAhead === 1 ? " day" : " days")
                        color: root.barForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.subtitle
                        font.bold: true
                    }
                    Ui.PanelActionButton {
                        id: settingsButton
                        iconText: "󰒓"
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        foreground: root.barForeground
                        focusable: true
                        Accessible.name: "Canvas settings"
                        tooltipText: "Settings"
                        onClicked: root.openSettings()
                    }
                }
                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.hostWidget ? (root.hostWidget.error || root.hostWidget.warnings.join("\n")) : ""
                    visible: text.length > 0
                    color: root.barForeground
                    wrapMode: Text.Wrap
                    font.pixelSize: Style.font.bodySmall
                }
                Text {
                    width: parent.width
                    text: !root.hostWidget ? "" : root.hostWidget.busy ? "Refreshing…" :
                        root.hostWidget.updatedAt ? (root.hostWidget.error ? "Last successful refresh: " : "Updated: ") +
                        Qt.formatDateTime(new Date(root.hostWidget.updatedAt), "ddd d MMM HH:mm") : "Not connected"
                    color: root.barForeground
                    font.pixelSize: Style.font.bodySmall
                }
                CanvasButton {
                    foreground: root.barForeground
                    text: "Refresh"
                    enabled: root.hostWidget && !root.hostWidget.busy && !root.hostWidget.needsSetup
                    onClicked: root.hostWidget.refresh()
                }
                CanvasButton {
                    foreground: root.barForeground
                    visible: root.hostWidget && root.hostWidget.needsSetup
                    text: "Connect Canvas and choose courses"
                    onClicked: root.openSettings()
                }
            }
            ListView {
                id: list
                visible: !root.showSettings
                anchors { top: header.bottom; topMargin: Style.space(12); left: parent.left; right: parent.right; rightMargin: Style.space(18); bottom: parent.bottom }
                clip: true
                spacing: Style.space(8)
                model: root.hostWidget ? root.hostWidget.assignments : []
                ScrollBar.vertical: CanvasScrollBar {
                    parent: list.parent
                    visible: list.visible && size < 1
                    foreground: root.barForeground
                    anchors { left: list.right; leftMargin: Style.space(8); top: list.top; bottom: list.bottom }
                }
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: list.width
                    height: details.implicitHeight + Style.space(20)
                    color: hit.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.1) : "transparent"
                    radius: Style.space(6)
                    border.width: 1
                    border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.2)
                    Column {
                        id: details
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(10) }
                        spacing: Style.space(4)
                        Text {
                            width: parent.width
                            text: row.modelData.name
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: root.barForeground
                            font.bold: true
                            font.pixelSize: Style.font.body
                        }
                        Text {
                            width: parent.width
                            text: row.modelData.course
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: root.barForeground
                            font.pixelSize: Style.font.bodySmall
                        }
                        Text {
                            width: parent.width
                            text: Qt.formatDateTime(new Date(row.modelData.due_at), "ddd d MMM · HH:mm") + " · " + row.modelData.status
                            wrapMode: Text.Wrap
                            color: root.barForeground
                            font.pixelSize: Style.font.bodySmall
                        }
                    }
                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally(row.modelData.url)
                    }
                }
                Text {
                    width: parent.width
                    visible: list.count === 0 && root.hostWidget && !root.hostWidget.busy && !root.hostWidget.error
                    text: root.hostWidget && root.hostWidget.warnings.length ? "Some courses could not be checked." :
                        root.hostWidget && root.hostWidget.selectedCourseCount === 0 ? "No courses selected. Choose courses in Settings." : "No assignments due in the next " + root.daysAhead + " days."
                    wrapMode: Text.Wrap
                    color: root.barForeground
                }
            }
            Loader {
                id: settingsLoader
                anchors.fill: parent
                active: root.showSettings
                visible: active
                sourceComponent: Settings {
                    foreground: root.barForeground
                    onboarding: root.hostWidget ? root.hostWidget.needsSetup : false
                    readerBusy: root.hostWidget ? root.hostWidget.busy : false
                    onConnectedAccount: {
                        if (!root.hostWidget) return
                        root.hostWidget.needsSetup = true
                        root.hostWidget.assignments = []
                        root.hostWidget.warnings = []
                        root.hostWidget.updatedAt = ""
                        root.hostWidget.error = "Choose courses in Settings to finish connecting."
                    }
                    onSaved: {
                        root.editingSettings = false
                        if (root.hostWidget) root.hostWidget.settingsSaved()
                    }
                    onCancelled: {
                        root.editingSettings = false
                    }
                }
            }
        }
    }
}

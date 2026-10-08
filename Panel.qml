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
    property date now: new Date()
    readonly property var taskModel: {
        var items = hostWidget ? hostWidget.assignments : []
        return items.map(function(item) {
            return Object.assign({}, item, { dueDay: Qt.formatDateTime(new Date(item.due_at), "yyyy-MM-dd") })
        })
    }
    function dayLabel(day) {
        var date = new Date(day + "T12:00:00")
        var tomorrow = new Date(now)
        tomorrow.setDate(tomorrow.getDate() + 1)
        var prefix = day === Qt.formatDateTime(now, "yyyy-MM-dd") ? "Today" :
            day === Qt.formatDateTime(tomorrow, "yyyy-MM-dd") ? "Tomorrow" : Qt.formatDateTime(date, "dddd")
        return prefix + "  " + Qt.formatDateTime(date, "d MMM")
    }
    Timer { interval: 60000; running: root.opened; repeat: true; onTriggered: root.now = new Date() }
    function openSettings() {
        editingSettings = true
        if (hostWidget) hostWidget.cancelRefresh()
    }
    onOpenedChanged: {
        root.now = new Date()
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
        padding: Style.space(10)
        focusTarget: root.showSettings ? (settingsLoader.item as Item) : keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(460))
        contentHeight: panel.fittedContentHeight(Style.space(500))
        Ui.PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            blocked: root.showSettings
            onCloseRequested: root.close()
            onMoveRequested: function(dx, dy) {
                if (!dy || list.count === 0) return
                list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + dy))
                list.positionViewAtIndex(list.currentIndex, ListView.Contain)
            }
            onActivateRequested: {
                if (list.currentItem) Qt.openUrlExternally(list.currentItem.assignment.url)
            }
            onTextKey: function(text) { if (text === "r" && root.hostWidget) root.hostWidget.refresh() }
            onTabRequested: function(direction) { root.switchPanel(direction) }
            Column {
                id: header
                visible: !root.showSettings
                width: parent.width
                spacing: Style.space(8)
                Row {
                    width: parent.width
                    Text {
                        width: parent.width - settingsButton.width - refreshButton.width
                        height: settingsButton.height
                        verticalAlignment: Text.AlignVCenter
                        text: "󰑭  Assignments"
                        color: root.barForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.subtitle
                        font.bold: true
                    }
                    Ui.PanelActionButton {
                        id: refreshButton
                        iconText: "󰑐"
                        foreground: root.barForeground
                        focusable: true
                        enabled: root.hostWidget && !root.hostWidget.busy && !root.hostWidget.needsSetup
                        Accessible.name: "Refresh assignments"
                        tooltipText: "Refresh (R)"
                        onClicked: root.hostWidget.refresh()
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
                Row {
                    spacing: Style.space(8)
                    CanvasBadge {
                        id: pendingBadge
                        text: (root.hostWidget ? root.hostWidget.notSubmittedCount : 0) + " not submitted"
                        foreground: Color.accent
                    }
                    Text {
                        height: pendingBadge.height
                        verticalAlignment: Text.AlignVCenter
                        text: "Next " + root.daysAhead + (root.daysAhead === 1 ? " day" : " days")
                        color: root.barForeground
                        opacity: 0.65
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                    }
                }
                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.hostWidget ? (root.hostWidget.error || root.hostWidget.warnings.join("\n")) : ""
                    visible: text.length > 0
                    color: Color.urgent
                    wrapMode: Text.Wrap
                    font.pixelSize: Style.font.bodySmall
                }
                Text {
                    width: parent.width
                    text: !root.hostWidget ? "" : root.hostWidget.busy ? "Refreshing…" :
                        root.hostWidget.updatedAt ? (root.hostWidget.error ? "Last successful refresh: " : "Updated: ") +
                        Qt.formatDateTime(new Date(root.hostWidget.updatedAt), "ddd d MMM HH:mm") : "Not connected"
                    color: root.barForeground
                    opacity: 0.6
                    font.pixelSize: Style.font.bodySmall
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
                anchors { top: header.bottom; topMargin: Style.space(8); left: parent.left; right: parent.right; rightMargin: assignmentScrollBar.visible ? assignmentScrollBar.width + Style.space(6) : 0; bottom: parent.bottom }
                clip: true
                spacing: Style.space(4)
                model: root.taskModel
                currentIndex: -1
                boundsBehavior: Flickable.StopAtBounds
                section.property: "dueDay"
                section.criteria: ViewSection.FullString
                section.delegate: Item {
                    id: daySection
                    required property string section
                    width: list.width
                    height: Style.space(34)
                    Text {
                        anchors { left: parent.left; bottom: parent.bottom; bottomMargin: Style.space(7) }
                        text: root.dayLabel(daySection.section)
                        color: root.barForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                    }
                }
                ScrollBar.vertical: CanvasScrollBar {
                    id: assignmentScrollBar
                    parent: list.parent
                    visible: list.visible && size < 1
                    foreground: root.barForeground
                    anchors { left: list.right; leftMargin: Style.space(6); top: list.top; bottom: list.bottom }
                }
                delegate: CanvasTaskRow {
                    required property var modelData
                    required property int index
                    width: list.width
                    height: implicitHeight
                    assignment: modelData
                    foreground: root.barForeground
                    now: root.now
                    selected: list.currentIndex === index
                    onActivated: Qt.openUrlExternally(assignment.url)
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

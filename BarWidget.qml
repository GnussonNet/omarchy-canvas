import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui

Ui.BarWidget {
    id: root
    moduleName: "gnussonnet.omarchy-canvas"
    property var assignments: []
    readonly property int notSubmittedCount: assignments.filter(function(assignment) {
        return assignment.status === "Not submitted"
    }).length
    property var warnings: []
    property string error: ""
    property string updatedAt: ""
    property bool needsSetup: false
    property int selectedCourseCount: 0
    property int daysAhead: 7
    property bool refreshCancelled: false
    readonly property bool busy: fetcher.running
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing : false
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function refresh() {
        if (!fetcher.running && !(panelLoader.item && panelLoader.item.showSettings)) {
            refreshCancelled = false
            fetcher.running = true
        }
    }
    function cancelRefresh() {
        refreshCancelled = true
        fetcher.running = false
    }
    function settingsSaved() {
        needsSetup = false
        assignments = []
        warnings = []
        updatedAt = ""
        error = ""
        Qt.callLater(refresh)
    }
    function open() { if (panelLoader.item) panelLoader.item.open() }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function toggle() { if (opened) close(); else open() }
    function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.bar = root.bar
        panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
    }
    onBarChanged: injectPanel()
    Component.onCompleted: refresh()
    Timer { interval: 300000; running: true; repeat: true; onTriggered: root.refresh() }
    Process {
        id: fetcher
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("canvas.py").toString().replace(/^file:\/\//, ""))]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (root.refreshCancelled) return
                try {
                    var result = JSON.parse(text)
                    if (result.ok) {
                        root.needsSetup = false
                        root.assignments = result.assignments
                        root.warnings = result.warnings
                        root.updatedAt = result.updated_at
                        root.selectedCourseCount = result.selected_course_count || 0
                        root.daysAhead = result.days_ahead || 7
                        root.error = ""
                    } else {
                        root.needsSetup = result.needs_setup === true
                        root.error = result.error
                        root.warnings = result.warnings || []
                    }
                } catch (e) { root.error = "Canvas reader failed. Check Python 3 is installed." }
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0 && !root.refreshCancelled) root.error = "Canvas reader failed. Check Python 3 is installed."
        }
    }
    Loader {
        id: panelLoader
        active: true
        visible: false
        source: Qt.resolvedUrl("Panel.qml")
        onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
    }
    Ui.WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: (root.needsSetup ? "Setup" : root.error ? "!" : root.notSubmittedCount) + (root.warnings.length ? " !" : "")
        labelVisible: false
        // Use the same outer inset as a standard icon slot.
        fixedWidth: vertical ? -1 : content.implicitWidth + Math.max(0, Style.bar.iconSlot - Style.bar.iconCanvas)
        fixedHeight: vertical ? content.implicitHeight + scaledVerticalPadding * 2 : -1
        tooltipText: "Not submitted assignments due in the next " + root.daysAhead + " days" + (root.busy ? " · Refreshing…" : "")
        onPressed: function(buttonCode) { if (buttonCode === Qt.LeftButton) root.toggle() }
        Item {
            id: content
            anchors.centerIn: parent
            implicitWidth: button.vertical ? Math.max(icon.width, count.implicitWidth) : icon.width + Style.space(4) + count.implicitWidth
            implicitHeight: button.vertical ? icon.height + count.implicitHeight : icon.height
            width: implicitWidth
            height: implicitHeight
            // Match BarIconButton's canvas and font metrics so the icon shares
            // the built-in icons' baseline rather than the counter's line box.
            Ui.OpticalGlyph {
                id: icon
                x: button.vertical ? (content.width - width) / 2 : 0
                width: Style.bar.iconCanvas
                height: Style.bar.iconCanvas
                text: "󰥔"
                fontFamily: button.fontFamily
                fontSize: Style.bar.iconFont
                color: button.foreground
            }
            Text {
                id: count
                x: button.vertical ? (content.width - width) / 2 : icon.width + Style.space(4)
                // Align actual baselines, not the centers of different line boxes.
                y: button.vertical ? icon.height : icon.baselineY - baselineOffset
                text: button.text
                textFormat: Text.PlainText
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
                color: button.foreground
                renderType: Text.NativeRendering
            }
        }
    }
}

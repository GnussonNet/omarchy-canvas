import QtQuick
import Quickshell.Io
import qs.Ui as Ui

Ui.BarWidget {
    id: root
    moduleName: "filip.canvas"
    property var assignments: []
    property var warnings: []
    property string error: ""
    property string updatedAt: ""
    readonly property bool busy: fetcher.running
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing : false
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function refresh() { if (!fetcher.running) fetcher.running = true }
    function open() { if (panelLoader.item) { refresh(); panelLoader.item.open() } }
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
                try {
                    var result = JSON.parse(text)
                    if (result.ok) {
                        root.assignments = result.assignments
                        root.warnings = result.warnings
                        root.updatedAt = result.updated_at
                        root.error = ""
                    } else root.error = result.error
                } catch (e) { root.error = "Canvas reader failed. Check Python 3 is installed." }
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) root.error = "Canvas reader failed. Check Python 3 is installed."
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
        text: "Canvas " + (root.error ? "!" : root.assignments.length) + (root.warnings.length ? " !" : "")
        tooltipText: "Assignments due in the next 7 days" + (root.busy ? " · Refreshing…" : "")
        onPressed: function(buttonCode) { if (buttonCode === Qt.LeftButton) root.toggle() }
    }
}

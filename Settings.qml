pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui

Item {
    id: root
    property color foreground: Color.foreground
    property bool onboarding: false
    property bool readerBusy: false
    property bool configured: false
    property string savedUrl: ""
    property string message: ""
    property var courses: []
    property var selectedIds: []
    property bool connected: false
    property int daysAhead: 7
    readonly property bool busy: metadata.running || saver.running
    readonly property bool saving: saver.running
    readonly property string script: decodeURIComponent(Qt.resolvedUrl("canvas.py").toString().replace(/^file:\/\//, ""))
    signal saved()
    signal connectedAccount()
    signal cancelled()
    focus: true

    function clearSecret() { tokenField.clear() }
    function loadCourses(result) {
        configured = result.configured
        savedUrl = result.url
        courses = result.courses || []
        selectedIds = result.selected_course_ids || []
        daysAhead = result.days_ahead || 7
    }
    function chooseCourse(courseId, checked) {
        var ids = selectedIds.slice()
        var index = ids.indexOf(courseId)
        if (checked && index < 0) ids.push(courseId)
        if (!checked && index >= 0) ids.splice(index, 1)
        selectedIds = ids
    }
    function save() {
        if (busy || readerBusy || !urlField.text.trim()) return
        message = ""
        saver.mode = "--save-settings"
        saver.payload = JSON.stringify({url: urlField.text.trim(), token: tokenField.text, days_ahead: daysField.field.value})
        clearSecret()
        saver.running = true
    }
    function saveCourses() {
        if (busy || !connected) return
        message = ""
        saver.mode = "--select-courses"
        saver.payload = JSON.stringify({url: savedUrl, selected_course_ids: selectedIds, days_ahead: daysField.field.value})
        saver.running = true
    }
    Keys.onEscapePressed: function(event) {
        event.accepted = true
        if (saver.running) return
        clearSecret()
        root.cancelled()
    }
    Component.onCompleted: metadata.running = true
    Process {
        id: metadata
        command: ["python3", root.script, "--settings-info"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    if (result.ok) {
                        root.loadCourses(result)
                        urlField.text = result.url
                        root.connected = result.configured && result.courses_loaded
                    } else root.message = result.error
                } catch (e) { root.message = "Could not load settings. Check Python 3 is installed." }
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) root.message = "Could not load settings. Check Python 3 is installed."
        }
    }
    Process {
        id: saver
        property string payload: ""
        property string mode: "--save-settings"
        command: ["python3", root.script, mode]
        stdinEnabled: true
        onStarted: {
            // Credentials travel through a pipe, never a command argument or shell.
            write(payload + "\n")
            payload = ""
        }
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    if (result.ok) {
                        root.loadCourses(result)
                        if (saver.mode === "--select-courses") Qt.callLater(function() { root.saved() })
                        else {
                            root.connected = true
                            root.connectedAccount()
                            root.message = "Connected. Choose your courses below, then save."
                        }
                    }
                    else root.message = result.error
                } catch (e) { root.message = "Could not save settings. Try again." }
            }
        }
        onExited: function(exitCode) {
            payload = ""
            root.clearSecret()
            if (exitCode !== 0) root.message = "Could not save settings. Check Python 3 is installed."
        }
    }
    Flickable {
        id: settingsScroll
        anchors.fill: parent
        anchors.rightMargin: Style.space(18)
        contentWidth: width
        contentHeight: settingsContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: CanvasScrollBar {
            parent: root
            foreground: root.foreground
            anchors { left: settingsScroll.right; leftMargin: Style.space(8); top: settingsScroll.top; bottom: settingsScroll.bottom }
        }
        Column {
            id: settingsContent
            width: settingsScroll.width
            spacing: Style.space(12)
            Text {
                width: parent.width
                text: "Canvas settings"
                color: root.foreground
                font.bold: true
                font.pixelSize: Style.font.title
                wrapMode: Text.Wrap
            }
            Text {
                width: parent.width
                text: "Connect to Canvas, then choose the courses you want to follow."
                color: root.foreground
                wrapMode: Text.Wrap
            }
            Label { text: "Canvas site URL"; color: root.foreground }
            Ui.TextField {
                id: urlField
                foreground: root.foreground
                width: parent.width
                enabled: !root.busy
                placeholderText: "https://school.instructure.com"
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
                selectByMouse: true
                onTextEdited: root.connected = false
                Accessible.name: "Canvas site URL"
                KeyNavigation.tab: tokenField
            }
            Label { text: "Access token"; color: root.foreground }
            Ui.TextField {
                id: tokenField
                foreground: root.foreground
                width: parent.width
                enabled: !root.busy
                echoMode: TextInput.Password
                passwordMaskDelay: 0
                inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                placeholderText: root.configured && urlField.text.trim() === root.savedUrl ? "Leave blank to keep saved token" : "Paste your Canvas access token"
                selectByMouse: true
                onTextEdited: root.connected = false
                Accessible.name: "Canvas access token"
                onAccepted: root.save()
                KeyNavigation.tab: saveButton
            }
            Text {
                width: parent.width
                text: "In Canvas, go to Account → Settings → Approved Integrations → New Access Token. Your school may need to enable this."
                color: root.foreground
                wrapMode: Text.Wrap
            }
            Text {
                width: parent.width
                text: "Your token is saved privately on this computer. Canvas access is read-only; this plugin never submits or changes assignments."
                color: root.foreground
                wrapMode: Text.Wrap
            }
            Text {
                width: parent.width
                visible: text.length > 0
                text: saver.running ? (saver.mode === "--save-settings" ? "Connecting and loading courses…" : "Saving courses…") : root.message
                textFormat: Text.PlainText
                color: root.foreground
                wrapMode: Text.Wrap
                Accessible.role: Accessible.AlertMessage
            }
            CanvasButton {
                id: saveButton
                foreground: root.foreground
                text: "Connect"
                enabled: !root.busy && !root.readerBusy && urlField.text.trim().length > 0
                onClicked: root.save()
            }
            Column {
                width: parent.width
                visible: root.connected
                spacing: Style.space(8)
                Ui.NumberField {
                    id: daysField
                    label: "Days ahead (default 7)"
                    foreground: root.foreground
                    from: 1
                    to: 90
                    value: root.daysAhead
                    enabled: !root.busy
                    onModified: function(value) { root.daysAhead = value }
                }
                Text {
                    width: parent.width
                    text: "Courses · " + root.selectedIds.length + " selected"
                    color: root.foreground
                    font.bold: true
                }
                Text {
                    width: parent.width
                    text: root.courses.length ? "Only checked courses are refreshed. Leave all unchecked to pause assignment fetching." : "No active student courses found for this account."
                    wrapMode: Text.Wrap
                    color: root.foreground
                }
                Repeater {
                    model: root.courses
                    Ui.Toggle {
                        required property var modelData
                        width: parent.width
                        label: modelData.name
                        foreground: root.foreground
                        checked: root.selectedIds.indexOf(modelData.id) >= 0
                        enabled: !root.busy
                        opacity: enabled ? 1 : 0.45
                        onClicked: root.chooseCourse(modelData.id, !checked)
                    }
                }
                CanvasButton {
                    foreground: root.foreground
                    text: "Save settings and show assignments"
                    enabled: !root.busy && !root.readerBusy
                    onClicked: root.saveCourses()
                }
            }
            CanvasButton {
                foreground: root.foreground
                text: "Back to assignments"
                enabled: !saver.running
                onClicked: { root.clearSecret(); root.cancelled() }
            }
        }
    }
}

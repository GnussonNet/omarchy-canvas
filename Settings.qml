pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui
import "CanvasStyle.js" as CanvasStyle

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
    property bool editingConnection: false
    property bool showTokenHelp: false
    property bool messageError: false
    property int daysAhead: 7
    readonly property bool busy: metadata.running || saver.running
    readonly property bool saving: saver.running
    readonly property string script: decodeURIComponent(Qt.resolvedUrl("canvas.py").toString().replace(/^file:\/\//, ""))
    signal saved()
    signal connectedAccount()
    signal cancelled()
    signal closeRequested()
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
        messageError = false
        saver.mode = "--save-settings"
        saver.payload = JSON.stringify({url: urlField.text.trim(), token: tokenField.text, days_ahead: daysField.field.value})
        clearSecret()
        saver.running = true
    }
    function saveCourses() {
        if (busy || !connected) return
        message = ""
        messageError = false
        saver.mode = "--select-courses"
        saver.payload = JSON.stringify({url: savedUrl, selected_course_ids: selectedIds, days_ahead: daysField.field.value})
        saver.running = true
    }
    Keys.priority: Keys.AfterItem
    Keys.onEscapePressed: function(event) {
        event.accepted = true
        if (saver.running) return
        clearSecret()
        root.closeRequested()
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
                    } else { root.message = result.error; root.messageError = true }
                } catch (e) { { root.message = "Could not load settings. Check Python 3 is installed."; root.messageError = true } }
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) { root.message = "Could not load settings. Check Python 3 is installed."; root.messageError = true }
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
                            root.editingConnection = false
                            root.messageError = false
                            root.connectedAccount()
                            root.message = "Connected. Choose your courses below, then save."
                        }
                    }
                    else { root.message = result.error; root.messageError = true }
                } catch (e) { { root.message = "Could not save settings. Try again."; root.messageError = true } }
            }
        }
        onExited: function(exitCode) {
            payload = ""
            root.clearSecret()
            if (exitCode !== 0) { root.message = "Could not save settings. Check Python 3 is installed."; root.messageError = true }
        }
    }
    Row {
        id: toolbar
        width: parent.width
        spacing: Style.space(10)
        CanvasButton {
            id: backButton
            foreground: root.foreground
            text: "󰁍 Back"
            enabled: !root.saving
            onClicked: { root.clearSecret(); root.cancelled() }
            Accessible.name: "Back to assignments"
        }
        Text {
            height: backButton.height
            verticalAlignment: Text.AlignVCenter
            text: "Canvas settings"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
        }
    }
    Column {
        id: feedback
        anchors { top: toolbar.bottom; topMargin: Style.space(8); left: parent.left; right: parent.right }
        Text {
            width: parent.width
            visible: text.length > 0
            text: root.busy ? (metadata.running ? "Loading settings…" : saver.mode === "--save-settings" ? "Connecting and loading courses…" : "Saving settings…") : root.message
            textFormat: Text.PlainText
            color: root.messageError ? Color.urgent : root.foreground
            opacity: root.messageError ? 1 : 0.7
            wrapMode: Text.Wrap
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            Accessible.role: Accessible.AlertMessage
        }
    }
    Flickable {
        id: settingsScroll
        anchors { top: feedback.bottom; topMargin: Style.space(10); left: parent.left; right: parent.right; bottom: root.connected ? footer.top : parent.bottom; bottomMargin: root.connected ? Style.space(10) : 0 }
        anchors.rightMargin: settingsScrollBar.visible ? settingsScrollBar.width + Style.space(6) : 0
        contentWidth: width
        contentHeight: settingsContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: CanvasScrollBar {
            id: settingsScrollBar
            parent: root
            visible: size < 1
            foreground: root.foreground
            anchors { left: settingsScroll.right; leftMargin: Style.space(6); top: settingsScroll.top; bottom: settingsScroll.bottom }
        }
        Column {
            id: settingsContent
            width: settingsScroll.width
            spacing: Style.space(16)
            Column {
                width: parent.width
                spacing: Style.space(8)
                Row {
                    width: parent.width
                    spacing: Style.space(8)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰌷 Connection"
                        color: root.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                    }
                    CanvasBadge {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.connected
                        text: "󰄬 Connected"
                        foreground: "#9ece6a"
                    }
                }
                Row {
                    width: parent.width
                    spacing: Style.space(8)
                    visible: root.connected && !root.editingConnection
                    CanvasButton {
                        id: editConnectionButton
                        anchors.verticalCenter: parent.verticalCenter
                        foreground: root.foreground
                        text: "Edit connection"
                        enabled: !root.busy
                        onClicked: root.editingConnection = true
                    }
                }
                Text {
                    width: parent.width
                    visible: root.connected && !root.editingConnection
                    text: root.savedUrl
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAnywhere
                    color: root.foreground
                    opacity: 0.6
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }
                Column {
                    width: parent.width
                    spacing: Style.space(6)
                    visible: !root.connected || root.editingConnection
                    Text { text: "Canvas site URL"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
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
                    Text { text: "Access token"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
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
                    Row {
                        spacing: Style.space(8)
                        CanvasButton {
                            id: saveButton
                            foreground: root.foreground
                            text: root.busy && saver.mode === "--save-settings" ? "Connecting…" : "Connect"
                            enabled: !root.busy && !root.readerBusy && urlField.text.trim().length > 0
                            onClicked: root.save()
                        }
                        CanvasButton {
                            foreground: root.foreground
                            text: root.showTokenHelp ? "Hide help" : "Token help"
                            onClicked: root.showTokenHelp = !root.showTokenHelp
                        }
                    }
                    Text {
                        width: parent.width
                        visible: root.showTokenHelp
                        text: "In Canvas: Account → Settings → Approved Integrations → New Access Token. Your school may need to enable this."
                        color: root.foreground
                        opacity: 0.7
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        text: "Stored privately on this computer. Canvas access is read-only."
                        color: root.foreground
                        opacity: 0.6
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        wrapMode: Text.Wrap
                    }
                }
            }
            Rectangle { width: parent.width; height: 1; color: root.foreground; opacity: 0.12 }
            Column {
                width: parent.width
                visible: root.connected
                spacing: Style.space(8)
                Text {
                    text: "󰃭 Deadline window"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                }
                Row {
                    width: parent.width
                    spacing: Style.space(10)
                    Ui.NumberField {
                        id: daysField
                        foreground: root.foreground
                        from: 1
                        to: 90
                        value: root.daysAhead
                        enabled: !root.busy
                        field.Accessible.name: "Days ahead"
                        onModified: function(value) { root.daysAhead = value }
                    }
                    Text {
                        height: daysField.height
                        verticalAlignment: Text.AlignVCenter
                        text: "days ahead"
                        color: root.foreground
                        opacity: 0.7
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                    }
                }
            }
            Column {
                width: parent.width
                visible: root.connected
                spacing: Style.space(6)
                Row {
                    width: parent.width
                    spacing: Style.space(8)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰑭 Courses"
                        color: root.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                    }
                    CanvasBadge {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.selectedIds.length + " selected"
                    }
                }
                Text {
                    width: parent.width
                    text: root.courses.length ? "Choose courses to follow. Deselect all to pause updates." : "No active student courses found."
                    color: root.foreground
                    opacity: 0.6
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.Wrap
                }
                Repeater {
                    model: root.courses
                    Rectangle {
                        id: courseRow
                        required property var modelData
                        readonly property bool checked: root.selectedIds.indexOf(modelData.id) >= 0
                        readonly property color courseColor: CanvasStyle.courseColor(modelData.id)
                        width: parent.width
                        height: Math.max(Style.space(36), courseName.implicitHeight + Style.space(14))
                        enabled: !root.busy
                        opacity: enabled ? 1 : 0.45
                        activeFocusOnTab: true
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, courseHit.containsMouse || activeFocus ? 0.09 : 0.025)
                        border.width: activeFocus ? 1 : 0
                        border.color: Color.accent
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: modelData.name
                        Accessible.checkable: true
                        Accessible.checked: checked
                        Accessible.onPressAction: root.chooseCourse(modelData.id, !checked)
                        Keys.onSpacePressed: root.chooseCourse(modelData.id, !checked)
                        Keys.onReturnPressed: root.chooseCourse(modelData.id, !checked)
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: Style.space(3)
                            color: courseRow.courseColor
                            opacity: courseRow.checked ? 1 : 0.35
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: Style.space(12); verticalCenter: parent.verticalCenter }
                            text: courseRow.checked ? "󰄲" : "󰄱"
                            color: courseRow.checked ? courseRow.courseColor : root.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                        }
                        Text {
                            id: courseName
                            anchors { left: parent.left; right: parent.right; leftMargin: Style.space(36); rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
                            text: courseRow.modelData.name
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: root.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                        }
                        MouseArea {
                            id: courseHit
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.chooseCourse(courseRow.modelData.id, !courseRow.checked)
                        }
                    }
                }
            }
        }
    }
    Column {
        id: footer
        visible: root.connected
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: Style.space(8)
        Rectangle { width: parent.width; height: 1; color: root.foreground; opacity: 0.12 }
        CanvasButton {
            width: parent.width
            foreground: root.foreground
            text: root.saving && saver.mode === "--select-courses" ? "Saving…" : "Save settings"
            enabled: root.connected && !root.busy && !root.readerBusy
            onClicked: root.saveCourses()
        }
    }
}

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons

Item {
    id: root
    property color foreground: "white"
    property bool onboarding: false
    property bool readerBusy: false
    property bool configured: false
    property string savedUrl: ""
    property string message: ""
    readonly property bool busy: metadata.running || saver.running
    readonly property bool saving: saver.running
    readonly property string script: decodeURIComponent(Qt.resolvedUrl("canvas.py").toString().replace(/^file:\/\//, ""))
    signal saved()
    signal cancelled()
    focus: true

    function clearSecret() { tokenField.clear() }
    function save() {
        if (busy || readerBusy || !urlField.text.trim()) return
        message = ""
        saver.payload = JSON.stringify({url: urlField.text.trim(), token: tokenField.text})
        clearSecret()
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
                        root.configured = result.configured
                        root.savedUrl = result.url
                        urlField.text = result.url
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
        command: ["python3", root.script, "--save-settings"]
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
                    if (result.ok) Qt.callLater(function() { root.saved() })
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
    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        Column {
            width: parent.width
            spacing: Style.space(12)
            Text {
                width: parent.width
                text: root.onboarding ? "Welcome to Omarchy Canvas" : "Canvas settings"
                color: root.foreground
                font.bold: true
                font.pixelSize: Style.font.title
                wrapMode: Text.Wrap
            }
            Text {
                width: parent.width
                text: root.onboarding ? "Connect your account to see assignments due in the next seven days." : "Update your Canvas site or replace your access token."
                color: root.foreground
                wrapMode: Text.Wrap
            }
            Label { text: "Canvas site URL"; color: root.foreground }
            TextField {
                id: urlField
                width: parent.width
                enabled: !root.busy
                placeholderText: "https://school.instructure.com"
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
                selectByMouse: true
                Accessible.name: "Canvas site URL"
                KeyNavigation.tab: tokenField
            }
            Label { text: "Access token"; color: root.foreground }
            TextField {
                id: tokenField
                width: parent.width
                enabled: !root.busy
                echoMode: TextInput.Password
                passwordMaskDelay: 0
                inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                placeholderText: root.configured && urlField.text.trim() === root.savedUrl ? "Leave blank to keep saved token" : "Paste your Canvas access token"
                selectByMouse: true
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
                text: saver.running ? "Checking connection…" : root.message
                textFormat: Text.PlainText
                color: root.foreground
                wrapMode: Text.Wrap
                Accessible.role: Accessible.AlertMessage
            }
            Button {
                id: saveButton
                text: root.onboarding ? "Connect Canvas" : "Test connection and save"
                enabled: !root.busy && !root.readerBusy && urlField.text.trim().length > 0
                onClicked: root.save()
            }
            Button {
                text: root.onboarding ? "Set up later" : "Cancel"
                enabled: !saver.running
                onClicked: { root.clearSecret(); root.cancelled() }
            }
        }
    }
}

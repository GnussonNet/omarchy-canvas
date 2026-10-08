import QtQuick
import qs.Commons

Rectangle {
    id: root
    required property var assignment
    property color foreground: Color.popups.text
    property bool selected: false
    property date now: new Date()
    readonly property bool submitted: assignment.status === "Submitted"
    readonly property bool actionable: assignment.status === "Not submitted" || assignment.status === "Resubmission requested"
    readonly property real hoursLeft: (new Date(assignment.due_at).getTime() - now.getTime()) / 3600000
    readonly property bool urgent: actionable && hoursLeft < 24
    readonly property color courseColor: {
        var colors = ["#7aa2f7", "#9ece6a", "#e0af68", "#bb9af7", "#7dcfff", "#f7768e"]
        var key = String(assignment.id).split(":")[0]
        var hash = 0
        for (var i = 0; i < key.length; i++) hash = (hash * 31 + key.charCodeAt(i)) >>> 0
        return colors[hash % colors.length]
    }
    readonly property color statusColor: submitted ? "#9ece6a" : urgent || assignment.status === "Resubmission requested" ? Color.urgent : actionable ? Color.accent : foreground
    signal activated()
    implicitHeight: details.implicitHeight + Style.space(14)
    radius: 0
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, hit.containsMouse || selected ? 0.09 : 0.025)
    border.width: selected ? 1 : 0
    border.color: Color.accent
    Accessible.role: Accessible.Link
    Accessible.name: assignment.name + ", " + assignment.course + ", " + assignment.status
    Accessible.onPressAction: activated()
    Rectangle {
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: Style.space(3)
        radius: 0
        color: root.courseColor
        opacity: root.submitted ? 0.45 : 1
    }
    Text {
        anchors { left: parent.left; leftMargin: Style.space(11); top: parent.top; topMargin: Style.space(8) }
        text: root.submitted ? "󰄬" : "󰄱"
        color: root.submitted ? root.statusColor : root.courseColor
        font.family: Style.font.family
        font.pixelSize: Style.font.body
    }
    Column {
        id: details
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: Style.space(34); rightMargin: Style.space(9); topMargin: Style.space(7) }
        spacing: Style.space(4)
        Text {
            width: parent.width
            text: root.assignment.name
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.foreground
            opacity: root.submitted ? 0.55 : 1
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: !root.submitted
            font.strikeout: root.submitted
        }
        Text {
            width: parent.width
            text: root.assignment.course
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.courseColor
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            opacity: root.submitted ? 0.6 : 1
        }
        Flow {
            width: parent.width
            spacing: Style.space(6)
            Text {
                height: statusBadge.height
                verticalAlignment: Text.AlignVCenter
                text: "󰥔 " + Qt.formatDateTime(new Date(root.assignment.due_at), "HH:mm")
                color: root.foreground
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
            }
            CanvasBadge {
                id: statusBadge
                text: root.assignment.status
                foreground: root.statusColor
            }
            CanvasBadge {
                visible: root.urgent
                text: root.hoursLeft < 0 ? "Past due" : root.hoursLeft < 1 ? "Due soon" : "Due in " + Math.ceil(root.hoursLeft) + "h"
                foreground: Color.urgent
            }
        }
    }
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}

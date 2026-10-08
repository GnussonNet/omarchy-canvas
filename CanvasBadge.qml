import QtQuick
import qs.Commons

Rectangle {
    id: root
    property string text: ""
    property color foreground: Color.accent
    implicitWidth: label.implicitWidth + Style.space(12)
    implicitHeight: label.implicitHeight + Style.space(6)
    radius: 0
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
    }
}

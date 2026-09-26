import QtQuick
import QtQuick.Controls
import qs.Commons

ScrollBar {
    id: root
    property color foreground: Color.foreground
    policy: ScrollBar.AsNeeded
    implicitWidth: Style.space(6)
    minimumSize: 0.08
    padding: 0
    contentItem: Rectangle {
        implicitWidth: Style.space(6)
        radius: width / 2
        color: root.foreground
        opacity: root.pressed ? 0.8 : root.hovered ? 0.6 : 0.3
    }
    background: Item {}
}

import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Core

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData
    anchors { top: true; left: true; right: true }
    implicitHeight: 32
    color: Theme.color.background

    Text {
        anchors.centerIn: parent
        text: "formalshell"
        color: Theme.color.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
    }
}

import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData
    anchors { top: true; left: true; right: true }
    implicitHeight: 32
    color: "#100F0F" // Flexoki black placeholder; Task 3 replaces with Theme token

    Text {
        anchors.centerIn: parent
        text: "formalshell"
        color: "#CECDC3"
        font.family: "monospace"
        font.pixelSize: 13
    }
}

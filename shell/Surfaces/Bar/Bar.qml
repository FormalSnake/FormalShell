import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Surfaces.Bar.widgets

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData
    anchors { top: true; left: true; right: true }
    implicitHeight: 32
    color: Theme.color.background

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.md
        anchors.rightMargin: Theme.spacing.md
        spacing: Theme.spacing.md

        Workspaces {
            Layout.alignment: Qt.AlignVCenter
            outputName: bar.screen ? bar.screen.name : ""
        }

        Item {
            Layout.fillWidth: true
        }

        ActiveWindow {
            Layout.alignment: Qt.AlignVCenter
            maxWidth: bar.width * 0.4
        }
    }
}

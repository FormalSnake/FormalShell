import QtQuick
import qs.Core
import qs.Components

// Bar cell for the wall clock (DESIGN.md §Bar's own "clock cell with TIME
// meta label" translation, spec §1, M6 Task 3): a TIME meta row over the
// hh:mm text, click toggles the calendar panel anchored under this cell —
// same panel-open accent dot idiom as AudioWidget.qml.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    property date _now: new Date()

    hovered: hoverArea.containsMouse

    Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.xs

        MetaLabel {
            text: "TIME"
        }

        Text {
            text: Qt.formatTime(root._now, "hh:mm")
            color: root.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
        }
    }

    Rectangle {
        visible: root._panelOpen
        width: 4
        height: 4
        radius: Theme.radius
        color: Theme.color.accent
        anchors.top: parent.top
        anchors.right: parent.right
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root._now = new Date()
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.panel)
                root.panel.toggle(root.mapToItem(null, 0, 0).x);
        }
    }
}

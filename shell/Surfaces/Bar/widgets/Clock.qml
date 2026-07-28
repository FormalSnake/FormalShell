import QtQuick
import qs.Core
import qs.Components

// Bar cell for the wall clock (DESIGN.md §3 Bar: a standalone discrete
// module with a TIME meta row over the hh:mm text), click toggles the
// calendar panel anchored under this cell — same panel-open accent dot
// idiom as AudioWidget.qml.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    property date _now: new Date()

    standalone: true
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
            font.pixelSize: Theme.fontSize.body
        }

        // Reserves the panel-open accent dot's own row in the layout
        // (DESIGN.md §3 Bar's "accent dot on the inner edge") instead of
        // free-floating it against the cell's outer bottom edge: Clock is
        // the two-line cell that sets Bar._cellHeight, so a dot anchored
        // straight to the cell's bottom has nowhere to go but into the
        // "hh:mm" text sitting right above it.
        Item {
            width: dot.width
            height: dot.height

            Rectangle {
                id: dot
                visible: root._panelOpen
                width: 4
                height: 4
                radius: Theme.radius
                color: Theme.color.accent
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
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

import QtQuick
import qs.Core
import qs.Components

// Bar cell for the wall clock (DESIGN.md §3 Bar, M23: single-line like
// every other widget here, hh:mm needs no meta label since the value
// alone is never ambiguous), click toggles the calendar panel anchored
// under this cell, same panel-open accent dot idiom as Battery.qml.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    property date _now: new Date()

    standalone: true
    hovered: hoverArea.containsMouse

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatTime(root._now, "hh:mm")
        color: root.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize.body
    }

    PanelOpenDot {
        visible: root._panelOpen
        inverted: root.invertedNow
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
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

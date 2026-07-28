import QtQuick
import qs.Core
import qs.Components

// Bar cell for the weather panel (DESIGN.md §Bar, spec §2's Location→
// Weather chain, M6 Task 8): an entry point only, mirroring Clock.qml's own
// "TIME" meta label — the widget shows a generic weather glyph rather than
// a live temperature so it never has to duplicate WeatherPanel's own
// open-meteo fetch/state (which only runs while the panel is open); click
// toggles the panel anchored under this cell, same panel-open accent dot
// idiom as every other M6 widget. Glyph taken from the pinned
// nerd-fonts-jetbrains-mono cmap (nix/testvm.nix) via fonttools ttx, not
// memory: weather-thermometer_exterior U+E34E.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    hovered: hoverArea.containsMouse

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.xs

        Text {
            text: ""
            color: root.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
        }

        MetaLabel {
            text: "WEATHER"
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

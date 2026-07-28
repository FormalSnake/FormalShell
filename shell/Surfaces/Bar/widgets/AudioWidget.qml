import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Bar cell for AudioService's default sink (DESIGN.md §Bar, spec §1, M6
// Task 1): volume glyph + percentage, click toggles the audio panel
// anchored under this cell. The panel-open accent dot (Omarchy detail,
// spec §1) sits in the cell's corner while the panel is open — a flat
// square, not a glyph, per DESIGN's "accent is a block, not a tint" rule.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    standalone: true
    hovered: hoverArea.containsMouse

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.xs

        Text {
            text: AudioService.muted ? "󰝟" : "󰕾"
            color: root.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }

        Text {
            text: Math.round(AudioService.volume * 100) + "%"
            color: root.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }
    }

    Rectangle {
        visible: root._panelOpen
        width: 4
        height: 4
        radius: Theme.radius
        color: Theme.color.accent
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
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

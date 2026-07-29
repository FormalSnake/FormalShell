import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Bar cell for MediaService's active player (DESIGN.md §Bar, spec §5, M7
// Task 1): a static note glyph, elided title, click toggles the media panel
// anchored under this cell — same panel-open accent dot idiom as every other
// M6 widget. Hidden entirely when no MPRIS player is registered (Battery.qml's
// own "no dead slot" rule) rather than a "nothing playing" lie. Glyph
// codepoint taken from the pinned nerd-fonts-jetbrains-mono cmap: md-music_note
// U+F0387.
Cell {
    id: root

    property var panel: null
    property real maxWidth: 220

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    // Read by Bar.qml's regionDelegate instead of `visible` directly — see
    // that file's own header comment for why crossing the Loader boundary
    // through the built-in `visible` property specifically breaks its own
    // future reactivity.
    readonly property bool shown: MediaService.available

    visible: root.shown
    standalone: true
    hovered: hoverArea.containsMouse

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.xs

        Text {
            text: "󰎇"
            color: root.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }

        Text {
            text: MediaService.title !== "" ? MediaService.title : MediaService.identity
            color: root.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
            elide: Text.ElideRight
            width: Math.min(implicitWidth, root.maxWidth)
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

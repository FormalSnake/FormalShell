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
    // Set from Bar.qml (`windowVisible: bar.visible`) so the marquee below
    // can gate on the bar's own PanelWindow actually being on screen — a
    // hidden-window ticker is exactly the CPU cost DESIGN.md's motion
    // carve-outs exist to avoid (M16 Task 11/12). Defaults true so any
    // other embedding still animates.
    property bool windowVisible: true

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    // Read by Bar.qml's regionDelegate instead of `visible` directly — see
    // that file's own header comment for why crossing the Loader boundary
    // through the built-in `visible` property specifically breaks its own
    // future reactivity.
    readonly property bool shown: MediaService.available

    visible: root.shown
    standalone: true
    hovered: hoverArea.containsMouse

    // The cell shows the title alone, and marquees or elides it once it
    // outgrows maxWidth — the tooltip adds the artist and, for a title that
    // was scrolling, lets it be read in one piece.
    tooltipText: {
        if (!root.shown)
            return "";
        var track = MediaService.title !== "" ? MediaService.title : MediaService.identity;
        return "NOW PLAYING / " + (MediaService.artist !== "" ? MediaService.artist + " / " : "") + track;
    }

    // Track title changes resize this cell — animate the width instead of
    // shoving the bar's other widgets instantly (DESIGN.md §4, M16 Task 2).
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰎇"
            color: root.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
        }

        // M16 Task 11 (owner-requested, gated subtle), extracted to
        // Components/MarqueeText.qml (M-polish batch item A) so
        // ActiveWindow.qml's title cell can reuse the identical mechanism:
        // a clipped two-copy marquee, ON ONLY when the title genuinely
        // overflows `maxWidth`, gated on Theme.motionEnabled AND the bar
        // window actually being on screen.
        MarqueeText {
            anchors.verticalCenter: parent.verticalCenter
            text: MediaService.title !== "" ? MediaService.title : MediaService.identity
            color: root.foreground
            maxWidth: root.maxWidth
            windowVisible: root.windowVisible
        }
    }

    PanelOpenDot {
        visible: root._panelOpen
        inverted: root.invertedNow
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

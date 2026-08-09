import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Bar cell for MediaService's active player (DESIGN.md §Bar, spec §5, M7
// Task 1): a note glyph, elided title, click toggles the media panel
// anchored under this cell — same panel-open accent dot idiom as every other
// M6 widget. Hidden entirely when no MPRIS player is registered (Battery.qml's
// own "no dead slot" rule) rather than a "nothing playing" lie. Glyph
// codepoint taken from the pinned nerd-fonts-jetbrains-mono cmap: md-music_note
// U+F0387.
//
// M20 Task 4b (owner: "the music icon can be replaced with the dithered
// album cover ... in a layout similar to the app icon in the menu bar"):
// the glyph above is the no-art fallback only. Once `MediaService.artUrl`
// resolves, a `DitherImage` takes its place at the same slot size
// ActiveWindow.qml's own app icon uses (a body-size Text's implicitHeight),
// radius 0, no border. M20 Task 5b: the cover renders in "retro" color
// dither and keeps its own colors even on a hovered (inverted) cell — the
// same content-keeps-its-colors ruling the menu's app icons already have —
// so unlike the rest of this cell's ink, the mini cover does NOT swap on
// hover. Static art only: the panel's animated Apple Music cover (AnimatedAlbumArt.qml)
// only decodes while the media panel itself is open, so sharing it at the
// bar would mean a second, permanently-idle Video pipeline for a slot this
// small: not worth it for a 16px icon (see DESIGN.md §3 Bar).
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
            id: glyph
            visible: MediaService.artUrl === ""
            anchors.verticalCenter: parent.verticalCenter
            text: "󰎇"
            color: root.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
        }

        // Dithered mini cover, glyph's own slot size (`glyph.implicitHeight`
        // still resolves while the glyph itself is hidden). Retro color
        // dither, content ruling: keeps the cover's own colors at rest and
        // on hover alike, unlike every other ink on this cell.
        DitherImage {
            visible: MediaService.artUrl !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: glyph.implicitHeight
            height: glyph.implicitHeight
            source: MediaService.artUrl
            mode: "retro"
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

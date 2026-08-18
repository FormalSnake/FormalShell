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
// hover.
//
// M35 (owner: "the bar cover doesnt appear to be animated ... the panel is
// fine" — reverses M20's "static only" call, DESIGN.md §2 item 12): a
// second DitherImage layers over the static one, sourced from
// `AnimatedCoverFrameSource.frameUrl` — the exact frames MediaPanel's own
// AnimatedAlbumArt.qml grabs off its one Video decode, republished rather
// than decoded twice for a slot this small. This cell registers as a
// frame consumer via `_syncFrames()` below (windowVisible + shown gate,
// VisualizerService.setBarVisible's own refcount idiom) so the shared
// decode runs whenever either this bar or the panel wants it.
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

    // M35: this cell wants animated frames exactly while it would actually
    // paint them — shown AND its bar window on screen — mirroring
    // Visualizer.qml's own windowVisible registration. AnimatedCoverFrameSource
    // ANDs in isPlaying/animatedArtUrl/motionEnabled itself, so those gates
    // don't need repeating here.
    readonly property bool _wantsFrames: root.shown && root.windowVisible
    property bool _registeredWantsFrames: false

    function _syncFrames() {
        if (root._wantsFrames === root._registeredWantsFrames)
            return;
        AnimatedCoverFrameSource.setBarWantsFrames(root._registeredWantsFrames, root._wantsFrames);
        root._registeredWantsFrames = root._wantsFrames;
    }

    on_WantsFramesChanged: root._syncFrames()
    Component.onCompleted: root._syncFrames()
    Component.onDestruction: {
        if (root._registeredWantsFrames)
            AnimatedCoverFrameSource.setBarWantsFrames(true, false);
    }

    // The cell shows the title alone, and marquees or elides it once it
    // outgrows maxWidth — the tooltip adds the artist and, for a title that
    // was scrolling, lets it be read in one piece. The trailing segment
    // states the M26 Task 9 right-click/scroll actions — otherwise they're
    // undiscoverable.
    tooltipText: {
        if (!root.shown)
            return "";
        var track = MediaService.title !== "" ? MediaService.title : MediaService.identity;
        return "NOW PLAYING / " + (MediaService.artist !== "" ? MediaService.artist + " / " : "") + track + " / RIGHT NEXT / SCROLL PREV NEXT";
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
        // on hover alike, unlike every other ink on this cell. The static
        // DitherImage below is the permanent fallback for every path the
        // animated overlay above it doesn't cover — disabled, no match, no
        // frame yet, motion off — same layering MediaPanel's artSlot uses.
        Item {
            id: coverSlot
            visible: MediaService.artUrl !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: glyph.implicitHeight
            height: glyph.implicitHeight

            DitherImage {
                anchors.fill: parent
                source: MediaService.artUrl
                mode: "retro"
            }

            // M35: shares AnimatedCoverFrameSource's frames with the panel's
            // own AnimatedAlbumArt.qml rather than decoding a second Video.
            DitherImage {
                anchors.fill: parent
                visible: AnimatedCoverFrameSource.active && AnimatedCoverFrameSource.frameUrl !== ""
                source: AnimatedCoverFrameSource.frameUrl
                mode: "retro"
            }
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

    interactive: true
    // M26 Task 9: right click skips ahead, scroll steps prev/next (up:
    // next, matching AudioWidget's own "up increases" scroll direction).
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            MediaService.next();
        } else if (root.panel) {
            root.panel.toggleFrom(root);
        }
    }
    onWheeled: wheel => {
        if (wheel.angleDelta.y > 0)
            MediaService.next();
        else
            MediaService.previous();
        wheel.accepted = true;
    }
}

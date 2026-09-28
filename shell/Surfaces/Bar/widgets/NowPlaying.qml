import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Bar cell for MediaService's active player (DESIGN.md §3 "Bar"): a music
// icon, the elided title in sans, and a click that toggles the media panel
// anchored under this cell, with the same open-panel underline every other
// widget draws. With no source at all it stays as the dimmed icon alone,
// since the media panel it opens is also where the radio is started: hiding
// it left no way to put anything on.
//
// The icon is the no-art fallback only. Once `MediaService.artUrl` resolves,
// the cover takes its place at the same slot size ActiveWindow.qml's own app
// icon uses (a body-size Text's implicitHeight). It is content imagery, so
// unlike the rest of this cell's ink it keeps its own colours on a filled
// cell.
//
// M35 (owner: "the bar cover doesnt appear to be animated ... the panel is
// fine"): a second Image layers over the static one, sourced from
// `AnimatedCoverFrameSource.frameUrl`, the exact frames MediaPanel's own
// AnimatedAlbumArt.qml grabs off its one Video decode, republished rather
// than decoded twice for a slot this small. This cell registers as a frame
// consumer via `_syncFrames()` below (windowVisible + shown gate,
// VisualizerService.setBarVisible's own refcount idiom) so the shared decode
// runs whenever either this bar or the panel wants it. Registering here is
// necessary but not sufficient: `media.animatedBarCover` (on by default)
// is what lets this cell's refcount reach the gate.
//
// M55 D7: Bar.qml's label refit narrows the title's own budget as the strip
// runs short of room (Bar/layout.js's labelBudgets, which shares it with the
// window title). The window title gives first, down to its own minimum,
// while this label holds `labelMin`; on a strip too short for both
// minimums the two split what room there is, and at a budget of 0 the
// label is gone but the cover or icon stays, the full title still in the
// tooltip this cell already carries.
Cell {
    id: root

    property var panel: null
    // Bar.qml's own cap: 220 or 15% of the strip, whichever is smaller.
    property real stripCap: 220
    readonly property real labelCap: Math.min(220, root.stripCap)
    // About twenty characters at the body size, the same width the window
    // title's app name stops at.
    readonly property real labelMin: Math.min(root.labelCap, Theme.space.popupWidthNarrow / 2)
    // Assigned by Bar.qml's label refit, never bound: the budget is worked
    // out from this cell's own extent, so a binding would close a loop.
    // Infinity until a bar has measured a strip, and wherever none hands one
    // out (the chevron's second bar); the cap alone holds then.
    property real labelBudget: Number.POSITIVE_INFINITY
    // What the title marquee actually gets, read by `bar room`.
    readonly property real maxWidth: Math.min(root.labelCap, root.labelBudget)
    // Set from Bar.qml (`windowVisible: bar.visible`) so the marquee below
    // can gate on the bar's own PanelWindow actually being on screen, a
    // hidden-window ticker is exactly the CPU cost DESIGN.md's motion
    // carve-outs exist to avoid (M16 Task 11/12). Defaults true so any
    // other embedding still animates.
    property bool windowVisible: true

    // What the title draws along the strip now and would draw uncapped,
    // the two numbers the refit reads. Zero with no source, where the
    // title slot is hidden and claims no room.
    readonly property real labelExtent: titleSlot.visible ? (root.vertical ? titleSlot.height : titleSlot.width) : 0
    readonly property real naturalLabelWidth: titleSlot.visible && titleSlot._front ? titleSlot._front._fullWidth : 0
    readonly property bool labelScrolling: titleSlot.visible && titleSlot._front ? titleSlot._front._marquee : false

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    // Read by Bar.qml's regionDelegate instead of `visible` directly, see
    // that file's own header comment for why crossing the Loader boundary
    // through the built-in `visible` property specifically breaks its own
    // future reactivity.
    readonly property bool shown: true

    visible: root.shown

    // M35: this cell wants animated frames exactly while it would actually
    // paint them, shown AND its bar window on screen, mirroring
    // Visualizer.qml's own windowVisible registration. AnimatedCoverFrameSource
    // ANDs in isPlaying/animatedArtUrl/motionEnabled itself, so those gates
    // don't need repeating here.
    readonly property bool _wantsFrames: MediaService.available && root.windowVisible
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
    // outgrows maxWidth, the tooltip adds the artist and, for a title that
    // was scrolling, lets it be read in one piece. The trailing segment
    // states the M26 Task 9 right-click/scroll actions, otherwise they're
    // undiscoverable.
    tooltipText: {
        if (!MediaService.available)
            return "NOTHING PLAYING / CLICK FOR THE RADIO";
        var track = MediaService.title !== "" ? MediaService.title : MediaService.identity;
        return "NOW PLAYING / " + (MediaService.artist !== "" ? MediaService.artist + " / " : "") + track + " / RIGHT NEXT / SCROLL PREV NEXT";
    }

    // Track title changes resize this cell, animate the width instead of
    // shoving the bar's other widgets instantly (DESIGN.md §4, M16 Task 2).
    // Both axes, since which one the cell grows along is the bar's edge.
    Behavior on implicitWidth {
        enabled: root.animateSize
        Anim {}
    }

    Behavior on implicitHeight {
        enabled: root.animateSize
        Anim {}
    }

    CellRow {
        spacing: Theme.space.xxs

        Icon {
            id: glyph
            visible: MediaService.artUrl === ""
            name: "music"
            size: Theme.fontSize.body
            color: MediaService.available ? root.foreground : root.dimForeground
        }

        // Mini cover, the glyph's own slot size (`glyph.implicitHeight`
        // still resolves while the glyph itself is hidden). Content imagery,
        // so it keeps the cover's own colours at rest and on hover alike,
        // unlike every other ink on this cell. The still underneath is the
        // permanent fallback for every path the animated overlay doesn't
        // cover (disabled, no match, no frame yet, motion off), the same
        // layering the media panel's own cover uses.
        //
        // `Cover` rounds it to a quarter of this slot, which at 17px is a
        // corner rather than a lozenge (owner, 2026-08-26).
        Cover {
            id: coverSlot
            visible: MediaService.artUrl !== ""
            width: glyph.implicitHeight
            height: glyph.implicitHeight
            source: MediaService.artUrl
            sourceSize.width: coverSlot.width
            sourceSize.height: coverSlot.height
            cache: false

            // M35: shares AnimatedCoverFrameSource's frames with the panel's
            // own AnimatedAlbumArt.qml rather than decoding a second Video.
            overlay: Picture {
                anchors.fill: parent
                visible: AnimatedCoverFrameSource.active && AnimatedCoverFrameSource.frameUrl !== ""
                source: AnimatedCoverFrameSource.frameUrl
                sourceSize.width: coverSlot.width
                sourceSize.height: coverSlot.height
                fillMode: Image.PreserveAspectCrop
                cache: false
            }
        }

        // M16 Task 11 (owner-requested, gated subtle), extracted to
        // Components/MarqueeText.qml (M-polish batch item A) so
        // ActiveWindow.qml's title cell can reuse the identical mechanism:
        // a clipped two-copy marquee, ON ONLY when the title genuinely
        // overflows `maxWidth`, gated on Theme.motionEnabled AND the bar
        // window actually being on screen.
        // Turned rather than stacked on a vertical bar, the same exception
        // ActiveWindow.qml's title makes and for the same reason: a track
        // title is free text of no fixed length (Bar/layout.js's
        // labelRotation). The slot swaps the marquee's own box, since a
        // rotated item still measures by the box it had before the turn.
        //
        // Two marquees rather than one, Icon.qml's own pattern (DESIGN.md §1
        // Motion, M53 D3): a track change installs the incoming title in
        // whichever slot is idle and `_cross` carries both opacities, so the
        // swap reads as one label changing under the cell's width morph
        // instead of cutting. Each slot restarts its own scroll off its own
        // measured width exactly as a single one did.
        Item {
            id: titleSlot
            visible: MediaService.available
            readonly property string _title: MediaService.title !== "" ? MediaService.title : MediaService.identity

            // 1 draws slot A, 0 draws slot B; the Behavior is on the driver
            // rather than on each slot's opacity so the two can never fall
            // out of step, and a title that changes again mid-fade retargets
            // this animation instead of restarting it.
            property real _cross: titleSlot._frontIsA ? 1 : 0
            property bool _frontIsA: true
            property bool _armed: false
            // `_title`'s own binding is evaluated during creation, which
            // emits a change of its own before the first install has run;
            // without this the very first title would arrive as a crossfade
            // out of an empty slot.
            property bool _ready: false
            property string _textA: ""
            property string _textB: ""

            readonly property Item _front: titleSlot._frontIsA ? titleA : titleB

            Behavior on _cross {
                Anim { kind: "effects" }
            }

            width: root.vertical ? titleSlot._front.height : titleSlot._front.width
            height: root.vertical ? titleSlot._front.width : titleSlot._front.height

            Component.onCompleted: {
                titleSlot._install(false);
                titleSlot._ready = true;
            }
            on_TitleChanged: {
                if (titleSlot._ready)
                    titleSlot._install(true);
            }

            function _install(animate) {
                if (animate && titleSlot._title === (titleSlot._frontIsA ? titleSlot._textA : titleSlot._textB))
                    return;

                if (!animate || !titleSlot._frontIsA)
                    titleSlot._textA = titleSlot._title;
                else
                    titleSlot._textB = titleSlot._title;
                if (!animate)
                    return;
                titleSlot._armed = true;
                titleSlot._frontIsA = !titleSlot._frontIsA;
            }

            MarqueeText {
                id: titleA
                anchors.centerIn: parent
                rotation: root.labelRotation
                text: titleSlot._textA
                color: root.foreground
                maxWidth: root.maxWidth
                opacity: titleSlot._cross
                // The slot that has faded out stops scrolling: this is the
                // same gate a hidden bar window uses, and a ticker nobody can
                // see is exactly the idle cost it exists to avoid.
                windowVisible: root.windowVisible && titleA.opacity > 0
            }

            MarqueeText {
                id: titleB
                visible: titleSlot._armed
                anchors.centerIn: parent
                rotation: root.labelRotation
                text: titleSlot._textB
                color: root.foreground
                maxWidth: root.maxWidth
                opacity: 1 - titleSlot._cross
                windowVisible: root.windowVisible && titleB.opacity > 0
            }
        }
    }

    panelOpen: root._panelOpen

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

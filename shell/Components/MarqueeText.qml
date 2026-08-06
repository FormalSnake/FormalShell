import QtQuick
import qs.Core

// Reusable clipped two-copy seamless marquee (extracted from NowPlaying.qml's
// M16 Task 11 now-playing title scroll, generalized for ActiveWindow.qml's
// window-title cell): renders `text` as a plain elided Text when it fits
// `maxWidth`, or scrolls it — a hold at the loop start, then a steady linear
// loop with no visible seam — once it genuinely overflows. Gated on
// Theme.motionEnabled AND `windowVisible` so a hidden window or a
// motion-disabled session never pays for a running animation; a title that
// fits never moves (DESIGN.md §4 rule 7).
Item {
    id: root

    property string text: ""
    property color color: Theme.color.foreground
    property int pixelSize: Theme.fontSize.body
    // Caps this item's WHOLE width, `leftPadding` included, so an embedder
    // that hands out a width budget gets an item that fits it exactly
    // instead of one overshooting by the padding and being clipped.
    property real maxWidth: 220
    // Extra inset before the text itself, on top of whatever Row spacing
    // already separates this from its previous sibling — plain QtQuick
    // Text has no leftPadding of its own, so this component provides one.
    property real leftPadding: 0
    // Set by the embedding widget so the marquee can gate on the window
    // actually being on screen — a hidden-window ticker is exactly the CPU
    // cost DESIGN.md's motion carve-outs exist to avoid. Defaults true so
    // any other embedding still animates.
    property bool windowVisible: true

    readonly property real _fullWidth: root.leftPadding + measureText.implicitWidth
    readonly property bool _overflow: root._fullWidth > root.maxWidth
    readonly property bool _marquee: root._overflow && Theme.motionEnabled && root.windowVisible
    // Blank between the two copies, sized off the text rather than the
    // spacing scale: at marqueePxPerSec a space.xl gap passes in a third of
    // a second, so the wrap reads as the title running into itself instead
    // of looping.
    readonly property real _gap: Math.round(root.pixelSize * 2.5)
    readonly property real _loopWidth: measureText.implicitWidth + root._gap

    width: Math.min(root._fullWidth, root.maxWidth)
    height: measureText.implicitHeight

    // A new overflowing title (window switch, track change) has to start at
    // the hold with its own left edge showing. `running` below stays true
    // straight through the swap, so nothing restarts the loop on its own and
    // the incoming title would otherwise pick up wherever the outgoing one
    // had scrolled to, staying wrong for up to a full cycle. Driven off the
    // measured width as well as `text` itself: Text lays out on the next
    // polish, so at onTextChanged `_loopWidth` is still the outgoing title's.
    function _restartMarquee() {
        if (!marqueeAnim.running)
            return;
        marqueeAnim.stop();
        marqueeRow.x = 0;
        marqueeAnim.start();
    }

    onTextChanged: root._restartMarquee()

    Text {
        id: measureText
        visible: false
        text: root.text
        font.family: Theme.font.family
        font.pixelSize: root.pixelSize
        onImplicitWidthChanged: root._restartMarquee()
    }

    // The scroll is clipped to start AFTER the inset, not at the item's own
    // left edge: clipping at the edge leaves the padding strip inside the
    // visible region, so a scrolling title slides straight into it and runs
    // up against whatever sits to the left (the app name, in ActiveWindow).
    // The inset only ever read as a gap while the loop sat at its hold.
    Item {
        id: viewport
        x: root.leftPadding
        width: root.width - root.leftPadding
        height: root.height
        clip: true

        Text {
            visible: !root._marquee
            text: root.text
            color: root.color
            font.family: Theme.font.family
            font.pixelSize: root.pixelSize
            elide: Text.ElideRight
            width: viewport.width
        }

        // Two copies of the title, a gap apart, scrolled together as one Row —
        // once `x` reaches `-_loopWidth` the second copy sits exactly where
        // the first one started, so the wrap is seamless with no reset
        // needed between loops.
        Row {
            id: marqueeRow
            visible: root._marquee
            spacing: 0

            Text {
                text: root.text
                color: root.color
                font.family: Theme.font.family
                font.pixelSize: root.pixelSize
            }
            Item { width: root._gap; height: 1 }
            Text {
                text: root.text
                color: root.color
                font.family: Theme.font.family
                font.pixelSize: root.pixelSize
            }
        }
    }

    // Hold at the loop start so the beginning is always readable, then
    // scroll the full loop width at a slow constant rate — no easing, since
    // a steady speed is the point (DESIGN.md §4).
    SequentialAnimation {
        id: marqueeAnim
        running: root._marquee
        loops: Animation.Infinite

        PauseAnimation { duration: Theme.motion.marqueeHoldMs }
        NumberAnimation {
            target: marqueeRow
            property: "x"
            from: 0
            to: -root._loopWidth
            duration: root._loopWidth / Theme.motion.marqueePxPerSec * 1000
            easing.type: Easing.Linear
        }
    }
}

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

    readonly property bool _overflow: measureText.implicitWidth > root.maxWidth
    readonly property bool _marquee: root._overflow && Theme.motionEnabled && root.windowVisible
    readonly property real _loopWidth: measureText.implicitWidth + Theme.space.xl

    width: root.leftPadding + Math.min(measureText.implicitWidth, root.maxWidth)
    height: measureText.implicitHeight
    clip: true

    Text {
        id: measureText
        visible: false
        text: root.text
        font.family: Theme.font.family
        font.pixelSize: root.pixelSize
    }

    Text {
        x: root.leftPadding
        visible: !root._marquee
        text: root.text
        color: root.color
        font.family: Theme.font.family
        font.pixelSize: root.pixelSize
        elide: Text.ElideRight
        width: root.width - root.leftPadding
    }

    // Two copies of the title, a gap apart, scrolled together as one Row —
    // once `x` reaches `leftPadding - _loopWidth` the second copy sits
    // exactly where the first one started, so the wrap is seamless with no
    // reset needed between loops.
    Row {
        id: marqueeRow
        x: root.leftPadding
        visible: root._marquee
        spacing: 0

        Text {
            text: root.text
            color: root.color
            font.family: Theme.font.family
            font.pixelSize: root.pixelSize
        }
        Item { width: Theme.space.xl; height: 1 }
        Text {
            text: root.text
            color: root.color
            font.family: Theme.font.family
            font.pixelSize: root.pixelSize
        }
    }

    // Hold at the loop start so the beginning is always readable, then
    // scroll the full loop width at a slow constant rate — no easing, since
    // a steady speed is the point (DESIGN.md §4).
    SequentialAnimation {
        running: root._marquee
        loops: Animation.Infinite

        PauseAnimation { duration: Theme.motion.marqueeHoldMs }
        NumberAnimation {
            target: marqueeRow
            property: "x"
            from: root.leftPadding
            to: root.leftPadding - root._loopWidth
            duration: root._loopWidth / Theme.motion.marqueePxPerSec * 1000
            easing.type: Easing.Linear
        }
    }
}

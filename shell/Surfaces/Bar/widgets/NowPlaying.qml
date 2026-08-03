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
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }

        // M16 Task 11 (owner-requested, gated subtle): a clipped two-copy
        // marquee, ON ONLY when the title genuinely overflows `maxWidth`.
        // Non-overflowing titles render exactly as before (a plain elided
        // Text) — `_marquee` is the single gate every other consumer here
        // reads. `measureText` is invisible-but-laid-out, giving both the
        // static and scrolling paths the same `implicitWidth` to size off.
        Item {
            id: titleClip
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(measureText.implicitWidth, root.maxWidth)
            height: measureText.implicitHeight
            clip: true

            readonly property bool _overflow: measureText.implicitWidth > root.maxWidth
            readonly property bool _marquee: titleClip._overflow && Theme.motionEnabled && root.windowVisible
            readonly property real _loopWidth: measureText.implicitWidth + Theme.space.xl

            Text {
                id: measureText
                visible: false
                text: MediaService.title !== "" ? MediaService.title : MediaService.identity
                font.family: Theme.font.family
                font.pixelSize: Theme.fontSize.body
            }

            Text {
                visible: !titleClip._marquee
                text: measureText.text
                color: root.foreground
                font.family: Theme.font.family
                font.pixelSize: Theme.fontSize.body
                elide: Text.ElideRight
                width: titleClip.width
            }

            // Two copies of the title, a gap apart, scrolled together as one
            // Row — once `x` reaches `-_loopWidth` the second copy sits
            // exactly where the first one started, so the wrap is seamless
            // with no reset needed between loops.
            Row {
                id: marqueeRow
                visible: titleClip._marquee
                spacing: 0

                Text {
                    text: measureText.text
                    color: root.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.body
                }
                Item { width: Theme.space.xl; height: 1 }
                Text {
                    text: measureText.text
                    color: root.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.body
                }
            }

            // Hold at the loop start so the beginning is always readable,
            // then scroll the full loop width at a slow constant rate — no
            // easing, since a steady speed is the point (DESIGN.md §4).
            SequentialAnimation {
                running: titleClip._marquee
                loops: Animation.Infinite

                PauseAnimation { duration: Theme.motion.marqueeHoldMs }
                NumberAnimation {
                    target: marqueeRow
                    property: "x"
                    from: 0
                    to: -titleClip._loopWidth
                    duration: titleClip._loopWidth / Theme.motion.marqueePxPerSec * 1000
                    easing.type: Easing.Linear
                }
            }
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

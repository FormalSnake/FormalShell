import QtQuick
import qs.Core

// One link of the power diagram: a `Separator`'s hairline, and while power
// really moves along it a stream of chevrons pointing the way it moves.
// `direction` is +1 toward the trailing end, -1 toward the leading one, 0 for
// no flow (no chevrons at all, so an idle link reads as a plain rule).
//
// The chevrons sit one `spacing` apart and the whole train shifts by exactly
// one spacing per cycle, so the wrap lands every chevron on its neighbour's
// old place and the stream never visibly jumps back. Each fades in and out
// over the last spacing at either end rather than popping at the clip. The
// train runs on the charging pulse's clock (DESIGN.md §1 "Motion", the
// continuous-motion carve-out) and holds still under `motion.enabled: false`.
// `animate` is the owner's arm switch: a panel that is closed passes false.
Item {
    id: root

    property int direction: 0
    property bool animate: true

    readonly property bool active: root.direction !== 0
    readonly property real spacing: Theme.fontSize.caption * 2
    property real phase: 0

    implicitHeight: Theme.fontSize.caption
    clip: true

    Separator {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
    }

    Repeater {
        model: root.active ? Math.ceil(root.width / root.spacing) + 1 : 0

        Icon {
            id: marker
            required property int index
            // Distance travelled from the link's source end.
            readonly property real along: (marker.index - 1 + root.phase) * root.spacing
            readonly property real fade: Math.max(0, Math.min(1,
                (marker.along + marker.width) / root.spacing,
                (root.width - marker.along - marker.width) / root.spacing))

            anchors.verticalCenter: parent.verticalCenter
            name: root.direction > 0 ? "chevron-right" : "chevron-left"
            size: Theme.fontSize.caption
            color: Theme.color.foreground
            opacity: marker.fade
            x: root.direction > 0 ? marker.along : root.width - marker.along - marker.width
        }
    }

    NumberAnimation on phase {
        running: root.active && root.animate && Theme.motionEnabled
        from: 0
        to: 1
        duration: Theme.motion.pulseDuration
        loops: Animation.Infinite
    }
}

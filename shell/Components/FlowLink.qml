import QtQuick
import qs.Core

// One link of the power diagram: a `Separator`'s hairline, and while power
// really moves along it a chevron pointing the way it moves. `direction` is
// +1 toward the trailing end, -1 toward the leading one, 0 for no flow (no
// chevron at all, so an idle link reads as a plain rule).
//
// The chevron travels the line on the charging pulse's clock (DESIGN.md §1
// "Motion", the continuous-motion carve-out) and stops there under
// `motion.enabled: false`, sitting mid-line, where its direction still reads.
// `animate` is the owner's arm switch: a panel that is closed passes false.
Item {
    id: root

    property int direction: 0
    property bool animate: true

    readonly property bool active: root.direction !== 0
    property real phase: 0.5

    implicitHeight: marker.height

    Separator {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
    }

    Icon {
        id: marker
        visible: root.active
        anchors.verticalCenter: parent.verticalCenter
        name: root.direction > 0 ? "chevron-right" : "chevron-left"
        size: Theme.fontSize.caption
        color: Theme.color.foreground
        x: (root.direction > 0 ? root.phase : 1 - root.phase) * Math.max(0, root.width - marker.width)
    }

    NumberAnimation on phase {
        running: root.active && root.animate && Theme.motionEnabled
        from: 0
        to: 1
        duration: Theme.motion.pulseDuration * 3
        loops: Animation.Infinite
    }
}

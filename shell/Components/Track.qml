import QtQuick
import qs.Core

// The one progress/slider groove (DESIGN.md §2): `muted` track, `primary`
// fill, `radiusSm` on both, `trackThickness` tall.
Rectangle {
    id: root

    // 0..1. Anything outside that clamps rather than overflowing the groove.
    property real value: 0

    readonly property real _fraction: Math.max(0, Math.min(1, root.value))

    implicitHeight: Theme.space.trackThickness
    radius: Theme.radiusSm
    color: Theme.color.muted

    Rectangle {
        height: parent.height
        width: root.width * root._fraction
        radius: Theme.radiusSm
        color: Theme.color.primary

        Behavior on width {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
        }
    }
}

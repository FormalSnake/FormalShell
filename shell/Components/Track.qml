import QtQuick
import qs.Core

// The one progress/slider groove (DESIGN.md §2): `primary` at 0.2 for the
// groove, `primary` for the fill, `radiusSm` on both, `trackThickness` tall.
//
// The groove is shadcn's own `primary/20` rather than `muted`: `muted` and
// `accent` resolve to the same zinc step in the dark fallback, so a groove
// painted `muted` vanishes on a row carrying a `selected` or `active` fill.
Rectangle {
    id: root

    // 0..1. Anything outside that clamps rather than overflowing the groove.
    property real value: 0

    // A single mark cut through groove and fill alike, at this fraction of
    // the width. Negative (the default) draws none. AudioPanel's stream
    // rails are the one user: their 0..1.5 range needs the 1.0 boundary
    // visible so crossing into overdrive reads as deliberate rather than as
    // a track that ran out of room.
    property real notch: -1

    readonly property real _fraction: Math.max(0, Math.min(1, root.value))

    implicitHeight: Theme.space.trackThickness
    radius: Theme.radiusSm
    color: Qt.alpha(Theme.color.primary, 0.2)

    Rectangle {
        height: parent.height
        width: root.width * root._fraction
        radius: Theme.radiusSm
        color: Theme.color.primary

        Behavior on width {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
        }
    }

    Rectangle {
        visible: root.notch >= 0
        x: root.width * root.notch - width / 2
        width: Theme.borderWidth
        height: parent.height
        color: Theme.color.background
    }
}

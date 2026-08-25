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
}

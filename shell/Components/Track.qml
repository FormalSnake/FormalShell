import QtQuick
import qs.Core

// The one progress/slider groove (DESIGN.md §2): `primary` at 0.2 for the
// groove, `primary` for the fill, `radiusSm` on both, `trackThickness` tall.
//
// Under `theme.dither` (M49 D3) the remainder carries DitherFill's checker
// over that colour, the era's own way of drawing "not yet". It is loaded
// only while the knob is on, so a shadcn install pays for no Canvas, and it
// paints the groove's full rect: the preset that turns it on squares the
// radius too, so there are no rounded corners for it to sit proud of.
//
// The groove is shadcn's own `primary/20` rather than `muted`: `muted` and
// `accent` resolve to the same zinc step in the dark fallback, so a groove
// painted `muted` vanishes on a row carrying a `selected` or `active` fill.
//
// A track can carry the keyboard cursor itself (MediaPanel's progress and
// volume), so the ring is drawn here rather than by a Cell wrapped around
// it: the same halo plus border swap Switch and Cell draw, sized off the
// groove but painted outside its bounds at `z: -1`, so the geometry a
// layout sees is identical with and without the ring.
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

    // The keyboard cursor (DESIGN.md §1 "Ring"), for a surface that
    // addresses the track as a row of its own.
    property bool cursor: false

    // Hover tracking, for a surface that moves its cursor under the pointer.
    // The area answers no button, so a caller's own press/drag area sits on
    // top and keeps every event it has today. That caller area must leave
    // `hoverEnabled` off: a hover-enabled item above this one consumes the
    // hover and `containsPointer` never turns true.
    property bool interactive: false

    readonly property bool containsPointer: pointer.containsMouse

    readonly property real _fraction: Math.max(0, Math.min(1, root.value))

    implicitHeight: Theme.space.trackThickness
    radius: Theme.radiusSm
    color: Qt.alpha(Theme.color.primary, 0.2)
    // A filled groove has no border of its own, so the cursor's border swap
    // is the only thing that gives it one.
    border.width: root.cursor ? Theme.borderWidth : 0
    border.color: Theme.color.ring

    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.ringWidth
        // Behind the groove's own fill, which is what keeps the halo a ring
        // rather than a wash over the track.
        z: -1
        visible: root.cursor
        radius: root.radius + Theme.ringWidth
        color: Theme.color.ring
        opacity: Theme.ringAlpha
    }

    Loader {
        anchors.fill: parent
        active: Theme.dither
        sourceComponent: DitherFill { anchors.fill: parent }
    }

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

    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: root.interactive
        acceptedButtons: Qt.NoButton
    }
}

import QtQuick
import qs.Core

// The panel-open accent dot (DESIGN.md §3 Bar: "a widget with an open panel
// gets omarchy's small accent dot on its inner edge"): every bar cell that
// owns an anchored panel/center shows this while that surface is open. Was
// duplicated verbatim (`width/height: 4`) in 11 widgets before this pass —
// one component, sized off `Theme.space.sm` instead of the bare literal.
//
// Positioning is the caller's own: most cells anchor this to their bottom
// edge, centered (`anchors.bottom: parent.bottom; anchors.horizontalCenter:
// parent.horizontalCenter`); Clock.qml instead reserves the dot's own row in
// a Column, since its cell's bottom edge sits right against the "hh:mm" text.
//
// `inverted` (DESIGN.md §1.1 bar-cell amendment): a hovered standalone cell's
// fill swaps to accent, so a plain accent dot vanishes into it — every
// caller binds this to its own cell's hover-inverted state (`Cell.qml`'s
// `invertedNow`) so the dot swaps to `onAccent` and stays visible instead.
Rectangle {
    property bool inverted: false

    width: Theme.space.sm
    height: Theme.space.sm
    radius: Theme.radius
    color: inverted ? Theme.color.onAccent : Theme.color.accent
}

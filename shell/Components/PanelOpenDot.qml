import QtQuick
import qs.Core

// The panel-open accent dot (DESIGN.md §3 Bar: "a widget with an open panel
// gets omarchy's small accent dot on its inner edge"): every bar cell that
// owns an anchored panel/center shows this while that surface is open. Was
// duplicated verbatim (`width/height: 4`) in 11 widgets before this pass —
// one component, sized off `Theme.space.sm` instead of the bare literal.
//
// Positioning is the caller's own: every cell anchors this to its bottom
// edge, centered (`anchors.bottom: parent.bottom; anchors.horizontalCenter:
// parent.horizontalCenter`).
//
// The negative bottom margin below is NOT cosmetic nudging. A caller's
// `parent` is Cell.qml's `content` item, which is inset by
// `controlPaddingY` on every side, so `content`'s bottom edge IS the text's
// bottom edge. Anchoring flush to it drew the dot straight through the
// glyphs. That went unnoticed while Clock.qml was a two-line cell setting
// Bar._cellHeight for everyone (M23 collapsed it): the extra height left
// every other cell's content box ~11px taller than its own text, and the
// dot lived in that slack. With the bar at one line there is no slack, so
// the dot has to be pushed back out into the padding band it always
// visually occupied. Cancelling exactly `controlPaddingY` lands it flush
// against the cell's outer bottom edge, which is DESIGN.md §3's "inner
// edge" (the edge facing the desktop) for a top bar. A caller setting its
// own `anchors.bottomMargin` overrides this.
//
// `inverted` (DESIGN.md §1.1 bar-cell amendment): a hovered standalone cell's
// fill swaps to accent, so a plain accent dot vanishes into it — every
// caller binds this to its own cell's hover-inverted state (`Cell.qml`'s
// `invertedNow`) so the dot swaps to `onAccent` and stays visible instead.
Rectangle {
    property bool inverted: false

    anchors.bottomMargin: -Theme.space.controlPaddingY

    width: Theme.space.sm
    height: Theme.space.sm
    radius: Theme.radius
    color: inverted ? Theme.color.onAccent : Theme.color.accent
}

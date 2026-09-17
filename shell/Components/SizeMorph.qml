import QtQuick
import qs.Core

// One size morph, for every surface that has one (DESIGN.md §1 "Motion",
// M51 D5, M53 D2, M57 D7). A card's width or height is the content's own
// target carried on `spatial`, and the rule around that target is the same
// wherever it appears:
//
// - tracked while the surface is open and frozen while it is closed, so a
//   change landing on a leaving card never moves it and the next open finds
//   the real content size instead of morphing out of the one the last close
//   left behind.
// - seeded without a clock on the open itself, so a fresh open lands where
//   it belongs rather than gliding there from that frozen size.
// - armed from the surface being MAPPED rather than from its enter having
//   settled. Content lands a tick or more after the open (the launcher's
//   keyed row sync, a Wi-Fi scan, a service's first poll), and a clock that
//   is off for the whole travel lets that change through in a single frame;
//   since a drawer's displacement is a function of the card's size across
//   the line, the far edge then jumps mid-travel instead of retargeting.
//   Armed here it retargets the running clock, and what hides the first
//   frames of it is the slit the card is coming out of.
// - off under `bypass`, for a consumer drawing its own trajectory over this
//   size (Panel's handoff): one clock on a size, never two.
// - and off under `held`, for the one size that is not data arriving: a card
//   whose content is rebuilt on every open measures itself while it is
//   arriving, and that first measurement is the card's own layout rather
//   than a change to it (M53 D2, dev/smoke.d/chevron_quiet.sh).
//
// `running` is what a consumer gates on: a place that is already a function
// of this value must not ride a clock of its own on top of it (Panel's
// `travel`), and the deform has to know the card is moving.
QtObject {
    id: root

    // The content's own size, live.
    property real target: 0
    property bool open: false
    // Whether the surface's own window is really up; see the header.
    property bool mapped: true
    property bool bypass: false
    // See the header: a consumer's hold over the frames its own content is
    // laying out in.
    property bool held: false

    // What the card is drawn at.
    property real value: 0

    readonly property bool running: clock.running

    // Down for the seed alone, so that one write lands with no clock under
    // it. Read by the Behavior at the instant of the write, which is why
    // setting it here and writing on the next line is enough.
    property bool _armed: false

    function _write(armed) {
        root._armed = armed;
        root.value = root.target;
    }

    onTargetChanged: if (root.open) root._write(root.mapped && !root.bypass && !root.held)
    onOpenChanged: if (root.open) root._write(false)
    Component.onCompleted: root._write(false)

    Behavior on value {
        enabled: root._armed
        Anim { id: clock }
    }
}

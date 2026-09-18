import QtQuick
import qs.Core
import "cursor.js" as Cursor

// The one progress/slider groove (DESIGN.md §2), drawn from the table's
// `track.groove` and `track.fill` roles, `trackThickness` tall.
//
// The groove is a `Box` and the fill a second box living inside it, clipped
// by nothing but its own width.
//
// Under `theme.dither` (M49 D3) the remainder carries DitherFill's checker
// over that colour, the era's own way of drawing "not yet". It is loaded
// only while the knob is on, so a shadcn install pays for no Canvas, and it
// paints the groove's full rect: the preset that turns it on squares the
// radius too, so there are no rounded corners for it to sit proud of.
//
// A track can carry the keyboard cursor itself (MediaPanel's progress and
// volume), so the ring is composed onto the groove's own box rather than
// drawn by a Cell wrapped around it: the same halo plus border swap Switch
// and Cell take, painted outside the groove's bounds, so the geometry a
// layout sees is identical with and without the ring.
Box {
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

    // A value that moves on a clock of its own rather than in steps (the
    // media panel's position, which is re-emitted every frame while the
    // lyrics pane is up). The fill's Behavior below animates one edge to a
    // new place, and a target that moves again before that animation has
    // been ticked restarts it from zero every time, so the fill stops where
    // it stood. A swept track writes its width straight instead.
    property bool swept: false

    // Hover tracking, for a surface that moves its cursor under the pointer.
    // The area answers no button, so a caller's own press/drag area sits on
    // top and keeps every event it has today. That caller area must leave
    // `hoverEnabled` off: a hover-enabled item above this one consumes the
    // hover and `containsPointer` never turns true.
    property bool interactive: false

    readonly property bool containsPointer: pointer.containsMouse

    readonly property real _fraction: Math.max(0, Math.min(1, root.value))

    role: "track.groove"

    readonly property var _grooveBox: Theme.box(root.role)
    readonly property var _fillBox: Theme.box("track.fill")

    // A filled groove has no border of its own, so the cursor's border swap
    // is the only thing that ever gives it one.
    readonly property var _cursorBorder: Theme.box("cursor").border

    implicitHeight: Theme.space.trackThickness

    // The cursor composed onto the groove (M59 T6): its border in place of
    // the groove's own, and its halo outside unless a list above draws one.
    // The border is held at the ring's colour with no width while the cursor
    // is elsewhere, so a groove taking it draws a line rather than fading
    // one up out of nothing.
    box: {
        if (root._cursorRing)
            return Theme.withCursor(root._grooveBox, root._cursorRing, !root._haloOwned);
        var rest = {};
        for (var key in root._grooveBox)
            rest[key] = root._grooveBox[key];
        rest.border = { color: root._cursorBorder.color, width: 0 };
        return rest;
    }

    // Whether something above this control draws the cursor halo for the
    // whole list it sits in (Panel.qml, M53 D4): one halo that travels
    // between rows needs there to be one of it. cursor.js carries the walk
    // and why it runs when the row takes the cursor rather than when it is
    // built.
    property bool _haloOwned: false

    // Whether the ring draws for this groove at all (DESIGN.md §1 "Ring"): the
    // list above it hands the ring to the keyboard and the wash to the
    // pointer, and a groove with no such list above it draws both. cursor.js
    // carries the walk, resolved on the same hop `_haloOwned` is.
    property Item _ringOwner: null
    readonly property bool _cursorRing: root.cursor
        && (!root._ringOwner || root._ringOwner.cursorFromKeys)

    onCursorChanged: if (root.cursor) {
        root._haloOwned = Cursor.haloOwned(root);
        root._ringOwner = Cursor.ringOwner(root);
    }

    Loader {
        anchors.fill: parent
        active: Theme.dither
        sourceComponent: DitherFill { anchors.fill: parent }
    }

    Rectangle {
        height: parent.height
        width: root.width * root._fraction
        radius: Theme.boxRadius(root._fillBox, parent.height)
        color: root._fillBox.fill

        // Not Linear: a level is set in steps by a poll or a drag, never
        // swept continuously, so every change is one on-screen edge
        // travelling to a new place rather than a constant rate.
        Behavior on width {
            enabled: !root.swept
            Anim { kind: "spatialFast" }
        }
    }

    Rectangle {
        visible: root.notch >= 0
        x: root.width * root.notch - width / 2
        width: Theme.borderWidth
        height: parent.height
        color: Theme.box("track.notch").fill
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: root.interactive
        acceptedButtons: Qt.NoButton
    }
}

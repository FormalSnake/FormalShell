import QtQuick
import qs.Core
import "cursor.js" as Cursor

// shadcn's switch (DESIGN.md §2): a `controlHeight` x `huge` track drawn
// from the table's `switch.track` role, off and on, with a `switch.knob`
// that slides between its two ends. The cursor is the ring, drawn exactly
// as Cell draws it.
//
// Track and knob are one `Box` each rather than one box holding the other:
// the knob rides the track, and the cursor's halo follows the track rather
// than the control's own square.
//
// Controlled, not self-toggling: `checked` is an input the owner binds to
// whatever it already stores (Center.qml binds NotificationService.dnd), and
// a click emits `toggled` with the value the owner should write. Flipping
// `checked` here would break that binding on the first press.
//
// No keys of its own either. The owning surface's KeyCatcher decides which
// key reaches which control and calls `toggle()`, the same division
// Panel.qml's cursor already draws.
Item {
    id: root

    property bool checked: false
    property bool cursor: false

    signal toggled(bool checked)

    function toggle() {
        root.toggled(!root.checked);
    }

    // Sized like every other control so it centres in any row it shares
    // with buttons; the track itself is the `huge` band in the middle.
    implicitWidth: Theme.space.controlHeight
    implicitHeight: Theme.space.controlHeight
    // `enabled` is QQuickItem's own: it gates the pointer target, and this
    // is the same dimming Button applies, so a disabled control reads the
    // same wherever it sits.
    opacity: root.enabled ? 1 : 0.5

    // The gap between the knob and the track, which is also how far the knob
    // sits from either end. Geometry, in hairlines, rather than a colour the
    // table would carry.
    readonly property real _inset: Theme.borderWidth * 2

    readonly property var _trackBox: Theme.box(track.role, root.checked ? "on" : "off")

    // A filled track has no border of its own, so the cursor's border swap
    // is the only thing that ever gives it one.
    readonly property var _cursorBorder: Theme.box("cursor").border

    // The cursor composed onto the track (M59 T6): its border in place of
    // the track's own, and its halo outside unless a list above draws one.
    readonly property var _box: {
        if (root.cursor)
            return Theme.withCursor(root._trackBox, root.cursor, !root._haloOwned);
        // Held at the ring's own colour with no width while the cursor is
        // elsewhere: the track carries no line of its own, so the one it
        // takes has to arrive as a line rather than as a colour fading up
        // out of nothing.
        var rest = {};
        for (var key in root._trackBox)
            rest[key] = root._trackBox[key];
        rest.border = { color: root._cursorBorder.color, width: 0 };
        return rest;
    }

    // Whether something above this control draws the cursor halo for the
    // whole list it sits in (Panel.qml, M53 D4): one halo that travels
    // between rows needs there to be one of it. cursor.js carries the walk
    // and why it runs when the row takes the cursor rather than when it is
    // built.
    property bool _haloOwned: false

    onCursorChanged: if (root.cursor) root._haloOwned = Cursor.haloOwned(root);

    Box {
        id: track
        role: "switch.track"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.space.huge
        box: root._box
    }

    Box {
        id: knob
        role: "switch.knob"
        width: track.height - root._inset * 2
        height: width
        y: track.y + root._inset
        x: root.checked ? root.width - width - root._inset : root._inset

        Behavior on x {
            Anim { kind: "spatialFast" }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
    }
}

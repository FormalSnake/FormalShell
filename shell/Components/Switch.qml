import QtQuick
import qs.Core
import "cursor.js" as Cursor

// shadcn's switch (DESIGN.md §2): a `controlHeight` x `huge` track drawn
// from the table's `switch.track` role, off and on, with a `switch.knob`
// that slides between its two ends. The cursor is the ring, drawn exactly
// as Cell draws it.
//
// The layers stay hand-drawn rather than composed out of a `Box`: the knob
// rides the track rather than sitting inside it, and the halo follows the
// track rather than the control's own square.
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

    readonly property var _trackBox: Theme.box("switch.track", root.checked ? "on" : "off")
    readonly property var _knobBox: Theme.box("switch.knob")

    // A filled track has no border of its own, so the cursor's border swap
    // is the only thing that ever gives it one.
    readonly property var _cursorBorder: Theme.box("cursor").border

    readonly property real _trackRadius: Theme.boxRadius(root._trackBox, Theme.space.huge)

    // Whether something above this control draws the cursor halo for the
    // whole list it sits in (Panel.qml, M53 D4): one halo that travels
    // between rows needs there to be one of it. cursor.js carries the walk
    // and why it runs when the row takes the cursor rather than when it is
    // built.
    property bool _haloOwned: false

    onCursorChanged: if (root.cursor) root._haloOwned = Cursor.haloOwned(root);

    Rectangle {
        anchors.fill: track
        anchors.margins: -Theme.ringWidth
        visible: root.cursor && !root._haloOwned
        radius: root._trackRadius + Theme.ringWidth
        color: Theme.cursorRing.color
    }

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.space.huge
        radius: root._trackRadius
        color: root._trackBox.fill
        border.width: root.cursor ? root._cursorBorder.width : 0
        border.color: root._cursorBorder.color

        Behavior on color {
            CAnim {}
        }
    }

    Rectangle {
        id: knob
        width: track.height - root._inset * 2
        height: width
        radius: Theme.boxRadius(root._knobBox, knob.height)
        y: track.y + root._inset
        x: root.checked ? root.width - width - root._inset : root._inset
        color: root._knobBox.fill

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

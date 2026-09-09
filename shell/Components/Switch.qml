import QtQuick
import qs.Core
import "cursor.js" as Cursor

// shadcn's switch (DESIGN.md §2): a `controlHeight` x `huge` track, `muted`
// off and `primary` on, with a `background` knob that slides between the
// two ends. The cursor is the ring, drawn exactly as Button and Cell draw
// it.
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
    // sits from either end.
    readonly property real _inset: Theme.borderWidth * 2

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
        radius: Theme.pillRadius(height)
        color: Theme.color.ring
        opacity: Theme.ringAlpha
    }

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.space.huge
        radius: Theme.pillRadius(height)
        color: root.checked ? Theme.color.primary : Theme.color.muted
        // A filled track has no border of its own, so the cursor's border
        // swap is the only thing that gives it one.
        border.width: root.cursor ? Theme.borderWidth : 0
        border.color: Theme.color.ring

        Behavior on color {
            CAnim {}
        }
    }

    Rectangle {
        id: knob
        width: track.height - root._inset * 2
        height: width
        radius: Theme.pillRadius(height)
        y: track.y + root._inset
        x: root.checked ? root.width - width - root._inset : root._inset
        color: Theme.color.background

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

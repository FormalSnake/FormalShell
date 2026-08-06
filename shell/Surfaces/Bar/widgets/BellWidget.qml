import QtQuick
import qs.Core
import qs.Components
import qs.Notifications

// Always-visible bar cell for notifications (DESIGN.md §3 Bar, M13b Task
// 2): bell glyph, swapping to bell-off while DND is on, plus a pending
// count meta label whenever NotificationService.pending is non-empty
// (under DND everything non-bypassing lands straight in pending, so the
// count keeps reading correctly with the bell-off glyph). Left click
// toggles the notification center — the same single Center instance
// `notifications showHistory` drives — with the panel-open accent dot
// idiom (AudioWidget) while it's open. Right click flips DND through
// NotificationService.setDnd, the one existing DND state machine
// (Core.State.dnd), never a second one. Glyph codepoints from the pinned
// nerd-fonts-jetbrains-mono cmap (nix/testvm.nix) via fonttools, not
// memory: md-bell U+F009A, md-bell_off U+F009B.
Cell {
    id: root

    property var center: null

    readonly property bool _dnd: NotificationService.dnd
    readonly property int _pending: NotificationService.pending.length
    readonly property bool _centerOpen: root.center ? root.center.isOpen : false

    standalone: true
    hovered: hoverArea.containsMouse

    // The bell-off glyph reads as "DND" only if you already know the pair,
    // and the bare count next to it doesn't say what it counts. Suppression
    // while the notification center is open is Tooltip.qml's job, not this
    // widget's — the center collides with a tooltip for EVERY right-region
    // cell, not just this one.
    tooltipText: root._dnd
        ? "NOTIFICATIONS / DND ON"
        : (root._pending > 0 ? "NOTIFICATIONS / " + root._pending + " PENDING" : "NOTIFICATIONS / NONE PENDING")

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root._dnd ? "󰂛" : "󰂚"
            color: root.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }

        MetaLabel {
            visible: root._pending > 0
            anchors.verticalCenter: parent.verticalCenter
            text: String(root._pending)
            color: root.foreground
        }
    }

    Rectangle {
        visible: root._centerOpen
        width: 4
        height: 4
        radius: Theme.radius
        color: Theme.color.accent
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                NotificationService.setDnd(!NotificationService.dnd);
            } else if (root.center) {
                if (root.center.isOpen)
                    root.center.close();
                else
                    root.center.open();
            }
        }
    }
}

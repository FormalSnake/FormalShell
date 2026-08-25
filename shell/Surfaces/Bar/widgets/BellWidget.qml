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
// `notifications showHistory` drives, with the open-panel underline
// (AudioWidget) while it's open. Right click flips DND through
// NotificationService.setDnd, the one existing DND state machine
// (Core.State.dnd), never a second one. A primary dot on the icon marks
// pending notifications, so the cell still says "something is waiting"
// with the count label switched off.
Cell {
    id: root

    property var center: null

    readonly property bool _dnd: NotificationService.dnd
    readonly property int _pending: NotificationService.pending.length
    readonly property bool _centerOpen: root.center ? root.center.isOpen : false

    // Visible by default (M23): the pending count is this cell's only
    // content, not a repeat of the glyph, so unlike weather/audio it stays
    // on unless a user opts out.
    readonly property bool _showLabel: Config.get("bar.widgets.bell.showLabel", true)

    standalone: true

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

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root._dnd ? "bell-off" : "bell"
            color: root.foreground

            Rectangle {
                visible: root._pending > 0
                anchors.right: parent.right
                anchors.top: parent.top
                width: Theme.space.md
                height: Theme.space.md
                radius: height / 2
                color: Theme.color.primary
            }
        }

        MetaLabel {
            visible: root._showLabel && root._pending > 0
            anchors.verticalCenter: parent.verticalCenter
            text: String(root._pending)
            color: root.foreground
            font.family: Theme.fontFamilyMono
        }
    }

    panelOpen: root._centerOpen

    interactive: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            NotificationService.setDnd(!NotificationService.dnd);
        } else if (root.center) {
            if (root.center.isOpen)
                root.center.close();
            else
                root.center.openFrom(root);
        }
    }
}

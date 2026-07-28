import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Notifications

// The popup toast stack (DESIGN.md §Notifications / spec §6): top-right,
// below the bar, one column of NotificationCard cells sharing rules like
// every other ledger surface (Cell.qml's shared-rule contract — the frame
// below draws the outer top/left rule, the Column runs zero-spacing).
// Passive overlay — no keyboard focus, click-through everywhere but the
// cards themselves (PanelWindow already only occupies the frame's own
// bounds, so nothing extra is needed there). One instance per screen, wired
// in shell.qml the same way as Bar/Background.
//
// Suppressed entirely while the history center is open: both are top-right
// anchored and a sticky critical popup (expiresAt = 0, never times out —
// see model.js's expire()) would otherwise sit permanently on top of the
// center's own top-right corner, both visually and for pointer input, since
// Toasts is on the Overlay layer above Center's Top layer. Hiding this
// surface for the duration costs nothing: the popup is still in
// NotificationService.popups, unaffected, and reappears the moment the
// center closes.
PanelWindow {
    id: root

    required property var modelData
    property var center: null
    screen: modelData

    // Bar.qml's implicitHeight is a bare literal (32), not a shared Theme
    // token — mirrored here so toasts start exactly at its bottom edge.
    readonly property int _barHeight: 32

    readonly property var _entries: NotificationService.popups
    visible: root._entries.length > 0 && !(root.center && root.center.isOpen)
    color: "transparent"

    // Relative timestamps ("2m ago") only ever recompute off this timer per
    // the plan-wide constraint — never off the reducer's own 1s tick.
    property double _now: Date.now()
    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        onTriggered: root._now = Date.now()
    }

    WlrLayershell.namespace: "formalshell:notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; right: true }
    margins {
        top: root._barHeight + Theme.spacing.md
        right: Theme.spacing.md
    }

    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight

    Item {
        id: frame
        implicitWidth: column.implicitWidth + Theme.borderWidth
        implicitHeight: column.implicitHeight + Theme.borderWidth
        width: implicitWidth
        height: implicitHeight

        // Outer top/left rule — Cell.qml's shared-rule contract makes every
        // cell draw its own bottom+right rule, so the frame only needs to
        // close off the top and left of the whole stack.
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.borderWidth
            color: Theme.color.rule
        }
        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Theme.borderWidth
            color: Theme.color.rule
        }

        Column {
            id: column
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.topMargin: Theme.borderWidth
            anchors.leftMargin: Theme.borderWidth
            spacing: 0

            Repeater {
                model: root._entries

                delegate: NotificationCard {
                    id: card
                    required property var modelData

                    entry: card.modelData
                    now: root._now

                    onDismiss: NotificationService.dismissPopup(card.modelData.id)
                    onBodyClicked: {
                        if (card.modelData.actions.some(a => a.key === "default"))
                            NotificationService.invokeAction(card.modelData.id, "default");
                        else
                            NotificationService.focusSender(card.modelData.id);
                    }
                    onActionInvoked: key => NotificationService.invokeAction(card.modelData.id, key)
                }
            }
        }
    }
}

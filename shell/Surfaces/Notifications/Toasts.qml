import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Notifications

// The popup toast stack (DESIGN.md §Notifications / spec §6): top-right,
// below the bar, one column of NotificationCard cells. Passive overlay — no
// keyboard focus, click-through everywhere but the cards themselves
// (PanelWindow already only occupies the column's own bounds, so nothing
// extra is needed there). One instance per screen, wired in shell.qml the
// same way as Bar/Background.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    // Bar.qml's implicitHeight is a bare literal (32), not a shared Theme
    // token — mirrored here so toasts start exactly at its bottom edge.
    readonly property int _barHeight: 32

    readonly property var _entries: NotificationService.popups
    visible: root._entries.length > 0
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

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    Column {
        id: column
        spacing: Theme.spacing.sm

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

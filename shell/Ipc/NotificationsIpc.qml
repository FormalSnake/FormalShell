import Quickshell.Io

import qs.Notifications

// `qs ipc call notifications status|dndState|toggleDnd|setDnd|showHistory|
// clear|clearPending|markAllSeen|dismissAll|invokeLast` — the
// notification-center half of the IPC surface; NotificationService's own
// dismissPopup/invokeAction stay unexposed here (Toasts.qml/Center.qml call
// them directly, keyed by a specific notification id, which isn't a
// CLI-friendly shape).
IpcHandler {
    target: "notifications"

    // Set from shell.qml — the single Center instance (same reasoning as
    // MenuIpc's `menu` property: one instance, no singleton of its own).
    property var center: null

    // One-shot observable state (MenuIpc's `status` pattern, M13b Task 2):
    // lets the smoke rig assert the bell widget's inputs (pending count,
    // dnd) and the center's open state without a screenshot — the bell's
    // own click calls the same center.open()/close() showHistory drives,
    // so proving that toggle over IPC stands in for the click.
    function status(): string {
        return JSON.stringify({
            dnd: NotificationService.dnd,
            pending: NotificationService.pending.length,
            popups: NotificationService.popups.length,
            centerOpen: center ? center.isOpen : false
        });
    }

    function dndState(): string {
        return NotificationService.dnd ? "on" : "off";
    }

    function toggleDnd(): string {
        NotificationService.setDnd(!NotificationService.dnd);
        return NotificationService.dnd ? "on" : "off";
    }

    function setDnd(on: bool): string {
        NotificationService.setDnd(on);
        return NotificationService.dnd ? "on" : "off";
    }

    function showHistory(): string {
        if (!center)
            return "error: center not ready";
        if (center.isOpen)
            center.close();
        else
            center.open();
        return "ok";
    }

    function clear(): string {
        NotificationService.dismissAll();
        NotificationService.clearPending();
        return "ok";
    }

    function clearPending(): string {
        NotificationService.clearPending();
        return "ok";
    }

    function markAllSeen(): string {
        NotificationService.markAllSeen();
        return "ok";
    }

    function dismissAll(): string {
        NotificationService.dismissAll();
        return "ok";
    }

    function invokeLast(): string {
        NotificationService.invokeLast();
        return "ok";
    }
}

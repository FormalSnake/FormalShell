import Quickshell.Io

import qs.Notifications

// `qs ipc call notifications dndState|toggleDnd|setDnd|showHistory|clear|
// clearPending|markAllSeen|dismissAll|invokeLast` — the notification-center
// half of the IPC surface; NotificationService's own dismissPopup/invokeAction
// stay unexposed here (Toasts.qml/Center.qml call them directly, keyed by a
// specific notification id, which isn't a CLI-friendly shape).
IpcHandler {
    target: "notifications"

    // Set from shell.qml — the single Center instance (same reasoning as
    // MenuIpc's `menu` property: one instance, no singleton of its own).
    property var center: null

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

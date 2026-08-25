import Quickshell.Io

import qs.Notifications
import "../Notifications/model.js" as Model

// `qs ipc call notifications status|dndState|toggleDnd|setDnd|showHistory|
// clear|clearPending|markAllSeen|dismissAll|dismissOne|invokeLast|expand`:
// the notification-center half of the IPC surface; NotificationService's own
// dismissPopup/invokeAction stay unexposed here (Toasts.qml/Center.qml call
// them directly, keyed by a specific notification id, which isn't a
// CLI-friendly shape).
IpcHandler {
    target: "notifications"

    // Set from shell.qml: the single Center instance (same reasoning as
    // MenuIpc's `menu` property: one instance, no singleton of its own).
    property var center: null

    // One-shot observable state (MenuIpc's `status` pattern, M13b Task 2):
    // lets the smoke rig assert the bell widget's inputs (pending count,
    // dnd) and the center's open state without a screenshot. The bell's
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

    // Drops the toast the stack shows in front, which is the newest group
    // unless a critical one outranks it (Model.stackOrder, the same order
    // Toasts.qml lays the collapsed pile out in). Group, not entry: the front
    // card stands for every repeat behind it, so this closes what the card's
    // own close button closes. Unrelated to NotificationService.dismissOne(id),
    // which drops one pending or past entry by id.
    //
    // `none` rather than an error when nothing is popped up: a keybind fired
    // at an empty screen is not a failure.
    function dismissOne(): string {
        var front = Model.stackOrder(Model.groupEntries(NotificationService.popups))[0];
        if (!front)
            return "none";
        NotificationService.dismissPopupGroup(front.memberIds);
        return "ok";
    }

    function invokeLast(): string {
        NotificationService.invokeLast();
        return "ok";
    }

    // Sonner-style stack expand/collapse (M34 Task 2, DESIGN.md
    // §Notifications): `on`/`off`, not a bool, matching how dndState/
    // toggleDnd/setDnd already report this exact shape as a return value,
    // and the rig types it as a bare word (`notifications expand on`)
    // rather than `true`/`false`. See NotificationService.stackExpanded
    // for why this lives there rather than in Core.State.
    function expand(state: string): string {
        if (state !== "on" && state !== "off")
            return "error: unknown expand state '" + state + "' (on|off)";
        NotificationService.setStackExpanded(state === "on");
        return NotificationService.stackExpanded ? "on" : "off";
    }
}

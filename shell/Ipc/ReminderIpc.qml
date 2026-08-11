import Quickshell.Io
import qs.Reminders

// `qs ipc call reminder set|show|clear|status` — countdown reminders for
// compositor keybinds and headless smoke verification. ReminderService owns
// every rule; this only forwards, so it never touches model.js itself.
//
// `set` takes BOTH arguments always. IPC arity is an exact-equality check
// (quickshell's ipccomm.cpp), so `qs ipc call reminder set 25m` is rejected
// before this handler runs, the same trap that produced the win+space menu
// regression MenuIpc documents. The no-message form is an explicit empty
// string: `qs ipc call reminder set 25m ""`, which fills the message from
// settings.json's reminders.defaultMessage.
//
// show vs status is a real division: `show` is the user-facing action (fire
// a notification listing what is pending, what a keybind calls), `status` is
// the machine-readable read a script or the smoke rig asserts against.
IpcHandler {
    target: "reminder"

    function set(duration: string, message: string): string {
        var entry = ReminderService.setFromParts(duration, message);
        if (!entry)
            return "error: could not read \"" + duration + "\" as a duration";
        return JSON.stringify({
            id: entry.id,
            message: entry.message,
            dueAt: entry.dueAt,
            dueClock: ReminderService.dueClock(entry.dueAt)
        });
    }

    function show(): string {
        ReminderService.showSummary();
        return "ok";
    }

    function clear(): string {
        return "ok: cleared " + ReminderService.clear();
    }

    function status(): string {
        var list = ReminderService.snapshot();
        return JSON.stringify({ count: list.length, reminders: list });
    }
}

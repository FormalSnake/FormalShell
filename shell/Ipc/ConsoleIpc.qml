import Quickshell.Io
import qs.Services

// `qs ipc call console toggle|show|hide|status`, the quake console (M37).
// `toggle` is what a compositor keybind binds to; the other three exist
// because a headless smoke run has no keyboard, and because a status dump
// is the only way to prove the window that comes back after a hide is the
// same one that went away.
IpcHandler {
    target: "console"

    function toggle(): string {
        ConsoleService.toggle();
        return "ok";
    }

    function show(): string {
        ConsoleService.show();
        return "ok";
    }

    function hide(): string {
        ConsoleService.hide();
        return "ok";
    }

    // `windowId` is "" when no console window exists, never a placeholder id:
    // "there is no console" and "the console is hidden" are different facts.
    function status(): string {
        return JSON.stringify({
            available: ConsoleService.available,
            appId: ConsoleService.appId,
            windowId: ConsoleService.windowId,
            visible: ConsoleService.showing,
            spawning: ConsoleService.spawning
        });
    }
}

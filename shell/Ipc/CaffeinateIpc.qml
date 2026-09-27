import Quickshell.Io

import qs.Services

// `qs ipc call caffeinate toggle|enable|disable|status`, for a compositor
// keybind and for driving an unattended host over ssh. status's
// `inhibiting` is the surface's own word that the Wayland inhibitor is
// mapped and enabled, not a restatement of `active`.
IpcHandler {
    target: "caffeinate"

    // Set from shell.qml, the single Caffeinate surface.
    property var caffeinate: null

    function toggle(): string {
        IdleService.toggleCaffeinated();
        return "ok";
    }

    function enable(): string {
        IdleService.setCaffeinated(true);
        return "ok";
    }

    function disable(): string {
        IdleService.setCaffeinated(false);
        return "ok";
    }

    function status(): string {
        return JSON.stringify({
            active: IdleService.caffeinated,
            inhibiting: caffeinate !== null && caffeinate.inhibiting,
            isIdle: IdleService.isIdle
        });
    }
}

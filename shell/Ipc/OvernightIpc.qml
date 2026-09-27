import Quickshell.Io

import qs.Core as Core
import qs.Services

// `qs ipc call overnight toggle|enable|disable|status`, for a compositor
// keybind and the smoke rig. status reports what OvernightService changed
// and will put back, null while it is off.
IpcHandler {
    target: "overnight"

    function toggle(): string {
        OvernightService.toggle();
        return "ok";
    }

    function enable(): string {
        OvernightService.enable();
        return "ok";
    }

    function disable(): string {
        OvernightService.disable();
        return "ok";
    }

    function status(): string {
        return JSON.stringify({
            active: OvernightService.active,
            restore: Core.State.overnight
        });
    }
}

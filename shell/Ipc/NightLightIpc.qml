import Quickshell.Io

import qs.Services

// `qs ipc call nightlight toggle|enable|disable|status` — spec addendum
// (M16 Task 6, the `panel`/`polkit` tradition, CLAUDE.md hard rules):
// drives NightLightService for compositor keybinds and the smoke rig.
// Every verb is zero-argument; there is nothing here for an unknown
// argument to hit.
IpcHandler {
    target: "nightlight"

    function toggle(): string {
        NightLightService.toggle();
        return "ok";
    }

    function enable(): string {
        NightLightService.enable();
        return "ok";
    }

    function disable(): string {
        NightLightService.disable();
        return "ok";
    }

    function status(): string {
        return JSON.stringify({
            active: NightLightService.active,
            temp: NightLightService.temp,
            lastError: NightLightService.lastError
        });
    }
}

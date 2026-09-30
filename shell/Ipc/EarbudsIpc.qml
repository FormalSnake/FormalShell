import Quickshell.Io

import qs.Services

// `qs ipc call earbuds status|devices|select <key>|set <control> <value>`,
// spec addendum (the `panel`/`bluetooth` tradition, CLAUDE.md hard rules):
// compositor keybinds and the smoke rig need a headless path onto the same
// controls the panel draws. `set` goes to the active device and takes the
// control key and a value as the panel would write it (`set noise anc`,
// `set ca on`, `set adaptive 40`); EarbudsService coerces it against the
// control and the backend's own allow-list, and a refusal comes back as an
// error string rather than a silent no-op.
IpcHandler {
    target: "earbuds"

    // The active device exactly as the panel renders it, or an honest
    // {available:false} / {device:null}.
    function status(): string {
        if (!EarbudsService.available)
            return JSON.stringify({ available: false });
        return JSON.stringify({ available: true, device: EarbudsService.active });
    }

    function devices(): string {
        return JSON.stringify(EarbudsService.devices.map(d => ({
            key: d.key,
            backend: d.backend,
            name: d.name,
            connected: d.connected,
            active: EarbudsService.active !== null && EarbudsService.active.key === d.key
        })));
    }

    function select(key: string): string {
        return EarbudsService.select(key) ? "ok" : "error: no device '" + key + "'";
    }

    function set(control: string, value: string): string {
        var error = EarbudsService.set(control, value);
        return error === "" ? "ok" : "error: " + error;
    }
}

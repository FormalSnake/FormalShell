import Quickshell.Io

import qs.Services

// `qs ipc call airpods status|noise <mode>|ca <on|off>|onebud <on|off>|ear
// <one|both|off>|adaptive <0-100>`, spec addendum (M29 Task 2, the
// `panel`/`bluetooth` tradition, CLAUDE.md hard rules): compositor keybinds
// and the smoke rig both need a headless drive path onto the librepods
// daemon's control socket. AirpodsService.send() already carries the wire
// allow-list (plan's research block, docs/superpowers/plans/2026-08-18-
// m29-device-panels.md); every verb here is built from a fixed prefix plus
// the caller's own argument and handed straight to it, so an unknown verb
// or an unset XDG_RUNTIME_DIR both come back as an honest error string
// rather than a silent no-op.
IpcHandler {
    target: "airpods"

    function _send(verb: string): string {
        if (!AirpodsService.send(verb))
            return "error: refused '" + verb + "'";
        return "ok";
    }

    function noise(mode: string): string {
        return _send("noise:" + mode);
    }

    function ca(state: string): string {
        return _send("ca:" + state);
    }

    function onebud(state: string): string {
        return _send("onebud:" + state);
    }

    function ear(mode: string): string {
        return _send("ear:" + mode);
    }

    function adaptive(level: string): string {
        return _send("adaptive:" + level);
    }

    // The parsed daemon state as-is, or an honest {available:false}, no
    // component here reshapes AirpodsService's own status object, so this
    // stays byte-for-byte what the panel itself renders from.
    function status(): string {
        if (!AirpodsService.available)
            return JSON.stringify({ available: false });
        var s = AirpodsService.status;
        return JSON.stringify({
            available: true,
            connected: s.connected,
            deviceName: s.deviceName,
            modelName: s.modelName,
            isPro: s.isPro,
            supportsOff: s.supportsOff,
            noiseMode: s.noiseMode,
            left: s.left,
            right: s.right,
            caseBattery: s.caseBattery,
            conversationalAwareness: s.conversationalAwareness,
            adaptiveNoiseLevel: s.adaptiveNoiseLevel,
            oneBudAnc: s.oneBudAnc,
            earDetection: s.earDetection,
            lidState: s.lidState
        });
    }
}

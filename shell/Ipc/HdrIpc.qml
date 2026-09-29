import Quickshell.Io

import qs.Services

// `qs ipc call hdr toggle|enable|disable|status`, for a compositor keybind.
// The zero-argument verbs act on every output whose EDID reports HDR;
// `setOutput` targets one. Each answers "ok" or why nothing changed.
// `rule <output>` prints the monitor rule an enable would send, unsent.
IpcHandler {
    target: "hdr"

    function toggle(): string {
        return HdrService.toggle();
    }

    function enable(): string {
        return HdrService.setAll(true);
    }

    function disable(): string {
        return HdrService.setAll(false);
    }

    function setOutput(output: string, enabled: bool): string {
        return HdrService.set(output, enabled);
    }

    function rule(output: string): string {
        return HdrService.ruleJson(output);
    }

    function status(): string {
        return HdrService.statusJson();
    }
}

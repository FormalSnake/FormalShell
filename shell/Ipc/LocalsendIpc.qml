import Quickshell.Io

import qs.Services

// `qs ipc call localsend status|peers|scan|send <peer> <path>`, the
// `panel`/`bluetooth`/`airpods` spec addendum tradition: compositor
// keybinds and the smoke rig both need a headless drive path onto
// LocalsendService. No `receive on|off`: `localsend.receive` is a
// settings.json key the service only ever reads, never a runtime toggle
// this target could flip, so there is nothing to expose beyond what
// `status` already reports it doing.
IpcHandler {
    target: "localsend"

    function status(): string {
        return JSON.stringify({
            installed: LocalsendService.installed,
            receiving: LocalsendService.receiving,
            alias: LocalsendService.alias,
            dir: LocalsendService.dir,
            scanning: LocalsendService.scanning,
            lastScanAt: LocalsendService.lastScanAt,
            peerCount: LocalsendService.peers.length,
            busy: LocalsendService.busy,
            sendTarget: LocalsendService.sendTarget,
            lastError: LocalsendService.lastError
        });
    }

    function peers(): string {
        return JSON.stringify(LocalsendService.peers);
    }

    function scan(): string {
        if (!LocalsendService.installed)
            return "error: localsend-cli is not installed";
        LocalsendService.scan(true);
        return "ok";
    }

    function send(peer: string, path: string): string {
        return LocalsendService.send(peer, [path]) ? "ok" : "error: unknown peer '" + peer + "'";
    }
}

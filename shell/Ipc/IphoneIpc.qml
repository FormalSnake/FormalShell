import Quickshell.Io

import qs.Services

// `qs ipc call iphone status|pair|invoke <id> <positive|negative>|dismiss
// <id>|clear|markRead`, spec addendum (the `panel`/`bluetooth`/`airpods`
// tradition, CLAUDE.md hard rules): compositor keybinds and the smoke rig
// both need a headless drive path onto IphoneService, the same reason every
// other device panel carries one. `status` answers exactly what the panel
// itself renders from, `installed: false` and nothing else when the bridge
// has never answered a line.
IpcHandler {
    target: "iphone"

    function status(): string {
        if (!IphoneService.installed)
            return JSON.stringify({ installed: false });
        return JSON.stringify({
            installed: true,
            available: IphoneService.available,
            connected: IphoneService.connected,
            bonded: IphoneService.bonded,
            bondAddress: IphoneService.bondAddress,
            deviceName: IphoneService.deviceName,
            batteryAvailable: IphoneService.batteryAvailable,
            battery: IphoneService.battery,
            unread: IphoneService.unread,
            inFocus: IphoneService.inFocus,
            pairingCode: IphoneService.pairingCode,
            advertising: IphoneService.advertising,
            lastError: IphoneService.lastError,
            mediaAvailable: IphoneService.mediaAvailable,
            mediaTitle: IphoneService.mediaTitle,
            recent: IphoneService.recent
        });
    }

    function pair(): string {
        return IphoneService.pair() ? "ok" : "error: no bridge on PATH";
    }

    function invoke(id: string, action: string): string {
        if (action !== "positive" && action !== "negative")
            return "error: action must be 'positive' or 'negative'";
        return IphoneService.invoke(Number(id), action === "positive")
            ? "ok" : "error: unknown notification '" + id + "'";
    }

    function dismiss(id: string): string {
        return IphoneService.dismiss(Number(id)) ? "ok" : "error: unknown notification '" + id + "'";
    }

    function clear(): string {
        IphoneService.clear();
        return "ok";
    }

    function markRead(): string {
        IphoneService.markRead();
        return "ok";
    }
}

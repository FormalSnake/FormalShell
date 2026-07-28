import Quickshell.Io

import qs.Services

// `qs ipc call clipboard list|copy|remove|clear` — the menu's clipboard
// provider node re-copies an entry via this same `copy` verb (see
// Menu/providers.js's clipboardProvider), so it doubles as the CLI surface
// and the menu's own activation path.
IpcHandler {
    target: "clipboard"

    function list(): string {
        return JSON.stringify(ClipboardService.items);
    }

    function copy(id: string): string {
        ClipboardService.copy(id);
        return "ok";
    }

    function remove(id: string): string {
        ClipboardService.remove(id);
        return "ok";
    }

    function clear(): string {
        ClipboardService.clear();
        return "ok";
    }
}

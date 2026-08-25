import Quickshell.Io

import qs.Services

// `qs ipc call clipboard list|copy|remove|clear`, the menu's clipboard
// provider node re-copies an entry via this same `copy` verb (see
// Menu/providers.js's clipboardProvider), so it doubles as the CLI surface
// and the menu's own activation path. Entries carry `kind: "text"|"image"`
// (M14 Task 6); image entries additionally carry `path`/`mime` instead of
// `text`, `list` surfaces whatever ClipboardService.items holds verbatim,
// and `copy` branches on `kind` internally (ClipboardService.qml).
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

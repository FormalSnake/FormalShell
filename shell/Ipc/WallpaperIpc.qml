import Quickshell.Io

import qs.Core as Core

// `qs ipc call wallpaper set|get`, setting a path here is the one trigger
// that starts the whole retheme pipeline (State.wallpaperChanged ->
// ThemeEngine.retheme()).
IpcHandler {
    target: "wallpaper"

    function set(path: string): string {
        if (path.charAt(0) !== "/")
            return "error: path must be absolute";
        Core.State.setWallpaper(path);
        return "ok";
    }

    function get(): string {
        return Core.State.wallpaper;
    }
}

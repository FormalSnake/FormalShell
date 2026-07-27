import Quickshell.Io

import qs.Theme
import qs.Core as Core

// `qs ipc call theme retheme|mode|status` — the theming half of the IPC
// surface; WallpaperIpc.qml covers wallpaper get/set.
IpcHandler {
    target: "theme"

    // ThemeEngine is a lazily-instantiated singleton (same as
    // CompositorService, see DebugIpc's _warmCompositor): nothing else in
    // the shipped shell ever reads a ThemeEngine property, so without this
    // touch here, at ThemeIpc's own construction, its startup probe (retheme
    // if theme.json is absent) and its Connections on State.wallpaper/mode
    // never activate — `wallpaper set` would update state.json and nothing
    // downstream would ever notice. Verified by reproducing the miss (state.json
    // written, theme.json never created) before adding this line.
    readonly property bool _warmThemeEngine: ThemeEngine.themeJsonPresent

    function retheme(): string {
        ThemeEngine.retheme();
        return "ok";
    }

    function mode(m: string): string {
        if (m === "toggle")
            Core.State.toggleMode();
        else if (m === "dark" || m === "light")
            Core.State.setMode(m);
        else
            return "error: mode must be dark, light, or toggle";
        return Core.State.mode;
    }

    function status(): string {
        return JSON.stringify({
            wallpaper: Core.State.wallpaper,
            mode: Core.State.mode,
            themeJsonPresent: ThemeEngine.themeJsonPresent
        });
    }
}

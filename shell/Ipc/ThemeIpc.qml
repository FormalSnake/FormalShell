import Quickshell.Io

import qs.Theme
import qs.Core as Core

// `qs ipc call theme retheme|mode|status`, the theming half of the IPC
// surface; WallpaperIpc.qml covers wallpaper get/set.
IpcHandler {
    target: "theme"

    // ThemeEngine is a lazily-instantiated singleton (same as
    // CompositorService, see DebugIpc's _warmCompositor): nothing else in
    // the shipped shell ever reads a ThemeEngine property, so without this
    // touch here, at ThemeIpc's own construction, its startup probe (retheme
    // if theme.json is absent) and its Connections on State.wallpaper/mode
    // never activate, `wallpaper set` would update state.json and nothing
    // downstream would ever notice. Verified by reproducing the miss (state.json
    // written, theme.json never created) before adding this line.
    readonly property bool _warmThemeEngine: ThemeEngine.themeJsonPresent

    function retheme(): string {
        ThemeEngine.retheme();
        return "ok";
    }

    // Every mode write goes through the engine: under `theme.mode: "auto"`
    // a flip is a snooze rather than a new resting mode, and a pinned key
    // refuses one outright.
    function mode(m: string): string {
        return ThemeEngine.requestMode(m);
    }

    // `mode` stays the live mode, the one this target flips; `modeKey` is
    // what settings.json asked for and `effective` what that key resolves
    // to now.
    function status(): string {
        return JSON.stringify({
            wallpaper: Core.State.wallpaper,
            mode: Core.State.mode,
            themeJsonPresent: ThemeEngine.themeJsonPresent,
            modeKey: ThemeEngine.modeKey,
            effective: ThemeEngine.effectiveMode(),
            schedule: ThemeEngine.scheduleStatus(),
            override: Core.State.modeOverride ? Core.State.modeOverride : null
        });
    }
}

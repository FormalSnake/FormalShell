import Quickshell.Io

import qs.Plugins

// `qs ipc call plugins list|status|reload`: introspection and lifecycle
// only. Summoning a plugin's panel or overlay stays on the existing `panel`
// target under its "plugin:<id>" name, so a plugin surface answers `panel
// open`/`toggle`/`close`/`state` exactly like a builtin one, and an unknown
// plugin name gets the same honest error an unknown builtin name gets.
//
// `status` is the one place a plugin's LOAD outcome is readable from outside
// the process: plugin QML lives outside the repo, so qmllint never sees it
// and its first syntax error would otherwise only exist as an engine message
// on stderr that nothing can read back.
IpcHandler {
    target: "plugins"

    function list(): string {
        return JSON.stringify(PluginService.plugins);
    }

    function status(): string {
        return JSON.stringify({
            directory: PluginService.directory,
            loaded: PluginService.loaded,
            count: PluginService.plugins.length,
            bar: PluginService.barPlugins.length,
            surface: PluginService.surfacePlugins.length,
            service: PluginService.servicePlugins.length,
            surfaces: Object.keys(PluginService.surfaces),
            errors: PluginService.errors,
            warnings: PluginService.warnings
        });
    }

    function reload(): string {
        PluginService.rescan();
        return "ok";
    }
}

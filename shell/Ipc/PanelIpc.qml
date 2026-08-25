import Quickshell.Io
import qs.Core
import qs.Plugins
import "../Bar/layout.js" as Layout
import "../Bar/panels.js" as Panels

// `qs ipc call panel open|close|toggle|toggleAt|state <name>` — spec addendum (this
// plan's own header note, M6 Task 1): per-widget popouts otherwise have no
// summon path for compositor keybinds and no way to be verified headlessly
// in the smoke rig. IPC-triggered opens have no bar cell to anchor under
// (no click happened), so they leave Panel.qml's anchorX unset and the
// frame falls back to sitting under the bar's right region. `registry` maps
// panel name -> its Panel instance, wired from shell.qml as each panel is
// added: appmenu, audio, calendar, network, bluetooth, airpods, dualsense,
// power, weather, media, github, usage, tailscale, systemupdate, display,
// monitor.
IpcHandler {
    id: root
    target: "panel"

    property var registry: ({})

    function open(name: string): string {
        var p = registry[name];
        if (!p)
            return "error: unknown panel '" + name + "'";
        p.open();
        return "ok";
    }

    function close(): string {
        for (var name in registry)
            if (registry[name].isOpen)
                registry[name].close();
        return "ok";
    }

    function toggle(name: string): string {
        var p = registry[name];
        if (!p)
            return "error: unknown panel '" + name + "'";
        p.toggle();
        return "ok";
    }

    // `qs ipc call panel toggleAt 3` (M42 D4, spec "Keyboard model" item 2):
    // the positional keybind, SUPER+CTRL+1..9 in the shipped example config.
    // The layout is resolved here rather than read off a Bar instance for the
    // same reason BarIpc does it: Bar.qml exists once per screen and this
    // handler answers for the whole shell, while Layout.resolve is pure and
    // re-runs on any Config change. Its warnings are dropped, since Bar.qml
    // already prints each one once per resolve.
    function toggleAt(n: int): string {
        var name = Panels.panelAt(Layout.resolve(Config.get("bar", null), PluginService.barPlugins), n);
        if (name === "")
            return "no panel at " + n;
        return root.toggle(name);
    }

    function state(): string {
        for (var name in registry)
            if (registry[name].isOpen)
                return name;
        return "";
    }
}

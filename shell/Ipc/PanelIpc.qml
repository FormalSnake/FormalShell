import Quickshell.Io

// `qs ipc call panel open|close|toggle|state <name>` — spec addendum (this
// plan's own header note, M6 Task 1): per-widget popouts otherwise have no
// summon path for compositor keybinds and no way to be verified headlessly
// in the smoke rig. IPC-triggered opens have no bar cell to anchor under
// (no click happened), so they leave Panel.qml's anchorX unset and the
// frame falls back to sitting under the bar's right region. `registry` maps
// panel name -> its Panel instance, wired from shell.qml as each panel is
// added: audio, calendar, network, bluetooth, power, weather, media,
// github, usage, tailscale, display.
IpcHandler {
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

    function state(): string {
        for (var name in registry)
            if (registry[name].isOpen)
                return name;
        return "";
    }
}

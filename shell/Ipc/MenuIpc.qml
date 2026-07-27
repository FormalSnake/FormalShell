import Quickshell.Io

// `qs ipc call menu toggle|summon|close|refresh|ping|select|input` — the
// menu's summon routes for direct compositor keybinds, plus the select/input
// dmenu-replacement modes. select/input can't return their result directly
// (IPC calls are synchronous request/response, the UI answer isn't): the
// chosen value (or a cancel) is instead written to
// $XDG_STATE_HOME/formalshell/menu-selection.txt as `{token, value}` /
// `{token, cancelled: true}` JSON, correlated by the caller-supplied token —
// callers poll/read that file. Menu.qml owns the actual write.
IpcHandler {
    target: "menu"

    // Set from shell.qml — the single Menu instance (see DebugIpc's `menu`
    // property for why: one instance, no singleton of its own).
    property var menu: null

    function toggle(route: string): string {
        if (!menu)
            return "error: menu not ready";
        if (menu.isOpen)
            menu.close();
        else
            menu.open(route);
        return "ok";
    }

    function summon(route: string): string {
        if (!menu)
            return "error: menu not ready";
        menu.open(route);
        return "ok";
    }

    function close(): string {
        if (!menu)
            return "error: menu not ready";
        menu.close();
        return "ok";
    }

    function refresh(): string {
        if (!menu)
            return "error: menu not ready";
        menu.refresh();
        return "ok";
    }

    function ping(): string {
        return "pong";
    }

    function select(prompt: string, optionsJson: string, token: string): string {
        if (!menu)
            return "error: menu not ready";
        var options;
        try {
            options = JSON.parse(optionsJson);
        } catch (e) {
            return "error: optionsJson must be a JSON array";
        }
        if (!Array.isArray(options))
            return "error: optionsJson must be a JSON array";
        menu.openSelect(prompt, options, token);
        return "ok";
    }

    function input(prompt: string, token: string): string {
        if (!menu)
            return "error: menu not ready";
        menu.openInput(prompt, token);
        return "ok";
    }
}

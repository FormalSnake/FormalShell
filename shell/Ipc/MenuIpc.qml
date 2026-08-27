import Quickshell.Io

// `qs ipc call menu toggle|summon|activate|close|refresh|ping|status|select|
// input`, the menu's summon routes for direct compositor keybinds, plus the
// select/input dmenu-replacement modes. select/input can't return their result directly
// (IPC calls are synchronous request/response, the UI answer isn't): the
// chosen value (or a cancel) is instead written to
// $XDG_STATE_HOME/formalshell/menu-selection.txt as `{token, value}` /
// `{token, cancelled: true}` JSON, correlated by the caller-supplied token,
// callers poll/read that file. Menu.qml owns the actual write.
IpcHandler {
    target: "menu"

    // Set from shell.qml, the single Menu instance (see DebugIpc's `menu`
    // property for why: one instance, no singleton of its own).
    property var menu: null

    // Deliberately no-argument (root summon if closed, close if open): the
    // win+space regression (M13) was a compositor keybind calling the old
    // toggle(route) with no argument at all, which IPC arity checking
    // rejects before the handler ever runs. A bare `qs ipc call menu
    // toggle` can't hit that trap; summon(route) below stays the
    // route-addressed path.
    function toggle(): string {
        if (!menu)
            return "error: menu not ready";
        if (menu.isOpen)
            menu.close();
        else
            menu.open(null);
        return "ok";
    }

    function summon(route: string): string {
        if (!menu)
            return "error: menu not ready";
        menu.open(route);
        return "ok";
    }

    // The rig's stand-in for Enter on the row at `index` (the same division
    // picker's choose() draws: the action a real Enter takes, exposed over
    // IPC rather than depending on unproven keyboard delivery into an
    // exclusive-focus layer surface). Backs the --menu emoji instant-paste
    // assertion.
    function activate(index: int): string {
        if (!menu)
            return "error: menu not ready";
        return menu.activate(index) ? "ok" : "error: menu not open";
    }

    // Shift+Enter on the row at `index`, the accelerator's own path: an app
    // row launched on the discrete card, a clipboard image row sent over
    // ssh. Same division activate() draws above, and the only way either is
    // provable headlessly.
    function activateAlternate(index: int): string {
        if (!menu)
            return "error: menu not ready";
        return menu.activateAlternate(index) ? "ok" : "error: menu not open";
    }

    // The rig's stand-in for typing into the search field, and the only way
    // to verify a route whose search field IS its content filter (the
    // process app view). Same division activate() draws above: real
    // keyboard delivery into an OnDemand-focus layer surface is not
    // provable headlessly.
    function filter(text: string): string {
        if (!menu)
            return "error: menu not ready";
        return menu.setQuery(text) ? "ok" : "error: menu not open";
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

    // Debug/verification hook (the smoke rig asserts the toggle round trip
    // through it): open/closed plus the current level's node id, null at
    // root. Same status() idiom as the lock/screenshot/tray targets.
    //
    // `placeholder`, `sections` and `columns` are the launcher's chrome
    // (M48): what the empty field says it is for, the group headings above
    // the rows in the order they appear, and how many cells wide the level
    // is (1 for a row list, the grid's own count for the wallpaper and emoji
    // routes). All three are otherwise only readable by measuring pixels off
    // a screenshot, which cannot tell a wide row from a grid at all.
    function status(): string {
        if (!menu)
            return "error: menu not ready";
        return JSON.stringify({
            isOpen: menu.isOpen,
            level: menu.currentNodeId,
            scrollTop: Math.round(menu.scrollTop),
            placeholder: menu.placeholder,
            sections: menu.sectionNames,
            columns: menu.cursorColumns,
            rows: menu.rowCount
        });
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

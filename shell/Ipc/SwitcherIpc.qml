import Quickshell.Io

import qs.Core

// `qs ipc call switcher next|prev|commit|cancel|state`, the whole summon path
// for the window switcher (M60 T6, the 2026-09-17 spec's Part 2). The
// surface takes the keyboard while it is open but never a modifier, so
// Alt+Tab, Alt+Shift+Tab and the commit on the modifier's release are the
// compositor's own binds calling in here
// (docs/examples/hyprland/formalshell.conf).
//
// `switcher.enabled: false` never instantiates the surface (shell.qml's
// Loader), and this target says so instead of accepting a call that would
// do nothing.
IpcHandler {
    id: root
    target: "switcher"

    // Set from shell.qml, the single Switcher instance, or null while
    // `switcher.enabled` is false (same reasoning as MenuIpc's `menu`
    // property: one instance, no singleton of its own).
    property var switcher: null

    readonly property string _off: "error: switcher is off (switcher.enabled)"

    function _guard() {
        if (Config.get("switcher.enabled", true) === false)
            return root._off;
        if (!switcher)
            return "error: switcher not ready";
        return "";
    }

    // Open with the cursor on the second entry if closed, advance if already
    // open, wrapping at either end. Two verbs rather than one with a
    // direction argument: these are what a keybind carries, and a bare
    // `switcher next` cannot trip the arity trap MenuIpc's `toggle` header
    // describes.
    function next(): string {
        var error = root._guard();
        if (error !== "")
            return error;
        switcher.step(1);
        return "ok";
    }

    function prev(): string {
        var error = root._guard();
        if (error !== "")
            return error;
        switcher.step(-1);
        return "ok";
    }

    // Focus the selected window and close. Honest about a commit with
    // nothing under the cursor: this verb is bound to the release of a
    // modifier, so it fires every time that modifier is let go, card open or
    // not, and a closed card commits nothing.
    function commit(): string {
        var error = root._guard();
        if (error !== "")
            return error;
        return switcher.commit() ? "ok" : "error: nothing to commit";
    }

    function cancel(): string {
        var error = root._guard();
        if (error !== "")
            return error;
        switcher.close();
        return "ok";
    }

    // Debug/verification hook (the smoke rig reads the cursor and the count
    // off it): the same status() idiom the lock/screenshot/tray targets
    // carry. The window id is the compositor's own opaque string, passed
    // through as it arrived.
    function state(): string {
        var error = root._guard();
        if (error !== "")
            return error;
        return JSON.stringify({
            open: switcher.isOpen,
            index: switcher.index,
            count: switcher.count,
            id: switcher.selectedId,
            title: switcher.selectedTitle
        });
    }
}

import Quickshell.Io
import qs.Compositor
import qs.Core
import qs.Plugins
import "../Bar/layout.js" as Layout
import "../Bar/panels.js" as Panels

// `qs ipc call panel open|close|toggle|toggleAt|state <name>`, spec addendum (this
// plan's own header note, M6 Task 1): per-widget popouts otherwise have no
// summon path for compositor keybinds and no way to be verified headlessly
// in the smoke rig. `open` has no bar cell to anchor under, so it leaves
// Panel.qml's anchorX unset and the frame falls back to sitting under the
// bar's right region. `toggle` and `toggleAt`, the two verbs a compositor
// keybind actually carries, resolve the cell off the bar itself (M53 D5) so
// a keyboard open hangs under its own widget rather than at the end of the
// strip. `registry` maps
// panel name -> its Panel instance, wired from shell.qml as each panel is
// added: appmenu, audio, calendar, network, bluetooth, airpods, dualsense,
// power, weather, media, github, usage, tailscale, systemupdate, display,
// monitor, trayoverflow.
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

    // The cell this panel hangs off, off the bar on the focused output, the
    // same output Panel's own no-screen fallback picks. A bar on another
    // output answers second, so a single-output session and a session whose
    // keyboard focus sits on a screen with no such cell both still land on a
    // cell rather than at the end of a strip. Null means no bar has one, and
    // the anchorless open below is the honest answer.
    function _anchor(name) {
        var bars = PanelRegistry.bars;
        var focused = CompositorService.focusedOutputName;
        var elsewhere = null;
        for (var i = 0; i < bars.length; i++) {
            var found = bars[i].panelAnchor(name);
            if (!found)
                continue;
            if (found.screen && found.screen.name === focused)
                return found;
            if (!elsewhere)
                elsewhere = found;
        }
        return elsewhere;
    }

    function toggle(name: string): string {
        var p = registry[name];
        if (!p)
            return "error: unknown panel '" + name + "'";
        var at = root._anchor(name);
        if (at)
            p.toggle(at.anchor, at.screen);
        else
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

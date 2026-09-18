import QtQuick
import Quickshell.Io
import "../../Compositor/keybinds.js" as Keybinds

// Compositor keybinds for the menu's keybinds route: `hyprctl binds`,
// already expanded across submaps and sourced files, so nothing here reads
// a config file or walks a lookup chain. The plain table, not `-j`: see
// parseHyprlandBinds for what Hyprland 0.56.0's JSON encoder does to that
// reply.
Item {
    id: root

    property string _text: ""
    property bool resolved: false
    property bool failed: false

    Process {
        id: proc
        command: ["hyprctl", "binds"]

        stdout: StdioCollector {
            id: collector
        }
        onExited: exitCode => {
            root.failed = exitCode !== 0;
            root._text = exitCode === 0 ? collector.text : "";
            root.resolved = true;
        }
    }

    function refresh() {
        if (!proc.running)
            proc.running = true;
    }

    // Every end state of the keybinds route resolves here, the same
    // one-function shape the nix provider's rowsFor takes. No SEARCHING
    // equivalent: the load is a sub-100ms hyprctl, so the one empty frame
    // before it lands has nothing to explain.
    function rowsFor(q) {
        if (!root.resolved) return [];
        if (root.failed) return [Keybinds.failedRow()];
        var binds = Keybinds.parseHyprlandBinds(root._text);
        if (binds.length === 0) return [Keybinds.noBindsRow()];
        return Keybinds.rows(binds, q);
    }
}

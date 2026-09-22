pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../Compositor/appicon.js" as AppIcon

// App icons for the launcher's rows and the window switcher's tiles, one
// resolver for both (Compositor/appicon.js carries the chain and why each
// tier is there). What lives here is what the pure half cannot reach: the
// icon theme, the live desktop entries, and the one /proc read a window
// needs when its class names no entry.
Singleton {
    id: root

    // Icon-name -> resolved source, memoised for the process. A themed name
    // is an XDG icon-theme lookup, which probes the theme directories on
    // disk, and the launcher resolves every installed app on each tree
    // rebuild. The answer only changes when the system icon theme does,
    // which does not happen under a running shell.
    property var _sources: ({})

    // `{ "<pid>": [{ exe, argv }, …] }`, the window's process and its
    // ancestors. Assigned whole rather than mutated, so a tile bound through
    // `forWindow` repaints when its pid's answer lands. A pid is read once:
    // it belongs to one process for as long as the window it came from is
    // alive.
    property var _procs: ({})
    property var _asked: ({})
    property var _queue: []

    function source(name) {
        var key = String(name || "");
        if (!root._sources[key])
            root._sources[key] = AppIcon.source(key, function (n) {
                return Quickshell.iconPath(n, true);
            });
        return root._sources[key];
    }

    function entryFor(win) {
        if (!win)
            return null;
        return AppIcon.entryFor(win, DesktopEntries.applications.values,
            root._procs[String(win.pid || 0)]);
    }

    // "" when nothing in the chain answers; the caller draws the generic
    // application icon then.
    function forWindow(win) {
        var entry = root.entryFor(win);
        return entry ? root.source(entry.icon) : "";
    }

    // Reads /proc for the windows whose class names no entry, once per pid.
    // The switcher calls this as it opens rather than on every window
    // event, so a session that never opens it never forks for it.
    function probe(windows) {
        var entries = DesktopEntries.applications.values;
        var wanted = root._queue.slice();
        for (var i = 0; i < (windows || []).length; i++) {
            var win = windows[i] || {};
            var pid = Number(win.pid || 0);
            if (!(pid > 1) || root._asked[pid] || AppIcon.byClass(win, entries))
                continue;
            root._asked[pid] = true;
            wanted.push(pid);
        }
        if (wanted.length === 0)
            return;
        if (procReader.running) {
            root._queue = wanted;
            return;
        }
        root._queue = [];
        procReader.command = AppIcon.procCommand(wanted);
        procReader.running = true;
    }

    Process {
        id: procReader
        stdout: StdioCollector {
            id: procText
        }
        onExited: {
            var next = Object.assign({}, root._procs);
            var read = AppIcon.parseProcs(procText.text);
            for (var pid in read)
                next[pid] = read[pid];
            root._procs = next;
            if (root._queue.length > 0)
                root.probe([]);
        }
    }
}

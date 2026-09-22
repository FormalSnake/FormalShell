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

    // Icon names a lookup has failed for, retried on a timer rather than
    // only on whatever unrelated event next rebuilds the caller's tree.
    // `Quickshell.iconPath` occasionally misses a name it resolves fine a
    // moment later (the icon theme's own cache still warming up right
    // after the shell starts), so a name earns one retry cycle rather than
    // being taken as permanently missing.
    property var _failed: ({})

    // Bumped when a retry recovers a name. `source()` reads it before its
    // cache check, so every binding that resolves an icon through it (an
    // app row's `iconSource`, a switcher tile, the bar's active-window
    // cell) depends on it too and repaints on its own, with no retry logic
    // of its own to write.
    property int generation: 0

    // `{ "<pid>": [{ exe, argv }, …] }`, the window's process and its
    // ancestors. Assigned whole rather than mutated, so a tile bound through
    // `forWindow` repaints when its pid's answer lands. A pid is read once:
    // it belongs to one process for as long as the window it came from is
    // alive.
    property var _procs: ({})
    property var _asked: ({})
    property var _queue: []

    function _themed(n) {
        return Quickshell.iconPath(n, true);
    }

    function source(name) {
        var key = String(name || "");
        root.generation; // read for the dependency described above
        if (!root._sources[key]) {
            var resolved = AppIcon.source(key, root._themed);
            root._sources[key] = resolved;
            if (key !== "") {
                if (resolved)
                    delete root._failed[key];
                else if (!root._failed[key]) {
                    root._failed[key] = true;
                    retryTimer.restart();
                }
            }
        }
        return root._sources[key];
    }

    // One retry pass over every name still failed. Reschedules itself
    // while any remain, so a theme that takes a couple of seconds to warm
    // up gets a couple of tries rather than one.
    function _retryFailed() {
        var keys = Object.keys(root._failed);
        if (keys.length === 0)
            return;
        var recovered = false;
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i];
            var resolved = AppIcon.source(key, root._themed);
            if (resolved) {
                root._sources[key] = resolved;
                delete root._failed[key];
                recovered = true;
            }
        }
        if (Object.keys(root._failed).length > 0)
            retryTimer.restart();
        if (recovered)
            root.generation++;
    }

    Timer {
        id: retryTimer
        interval: 750
        onTriggered: root._retryFailed()
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

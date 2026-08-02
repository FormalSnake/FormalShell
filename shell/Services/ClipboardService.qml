pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../Clipboard/history.js" as History

// Capture via `wl-paste --type text --watch <cmd>` under a long-running
// Process (verified against the wl-clipboard 2.3.0 man page in the store):
// wl-paste forks <cmd> on every clipboard change, connects its stdin to the
// new selection, and sets CLIPBOARD_STATE in its environment (`data` | `nil`
// | `clear` | `sensitive` — `sensitive` is the one wl-paste itself derives
// from an `x-kde-passwordManagerHint` mime, the cheap password-manager
// signal the plan asks for). The spawned shell one-liner below skips
// forwarding sensitive captures at all; nil/clear captures still reach
// history.js's sanitize() as empty text and are dropped there. Entries are
// NUL-delimited on stdout (clipboard text can itself contain newlines) and
// split with a SplitParser whose marker is the NUL character above.
//
// History persists to $XDG_STATE_HOME/formalshell/clipboard.json via the
// same FileView+JsonAdapter pattern Core/State.qml uses for state.json —
// this file is its own, separate from state.json, per the plan's Task 2.
Singleton {
    id: root

    readonly property string _stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/formalshell";
    }

    property alias items: adapter.items

    property int _idSeq: 0
    function _nextId() {
        root._idSeq += 1;
        return Date.now() + "-" + root._idSeq;
    }

    function _capture(text) {
        var result = History.add({ items: root.items }, { id: root._nextId(), text: text }, Date.now());
        if (result.state.items !== root.items)
            adapter.items = result.state.items;
    }

    function copy(id) {
        var entry = root.items.find(function (i) { return i.id === id; });
        if (!entry)
            return;
        copyProc.exec({ command: ["wl-copy", entry.text] });
    }

    function remove(id) {
        var result = History.remove({ items: root.items }, id);
        if (result.state.items !== root.items)
            adapter.items = result.state.items;
    }

    function clear() {
        var result = History.clear({ items: root.items });
        if (result.state.items !== root.items)
            adapter.items = result.state.items;
    }

    FileView {
        id: historyFile
        path: root._stateDir + "/clipboard.json"
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: adapter
            property var items: []
        }
    }

    Process {
        id: copyProc
    }

    // sh -c one-liner: `cat` forwards the selection, then a NUL byte marks
    // the entry boundary — skipped entirely (no NUL emitted either) when
    // CLIPBOARD_STATE says the selection is a password-manager hint.
    Process {
        id: watcher
        command: ["wl-paste", "--type", "text", "--watch", "sh", "-c",
            "[ \"$CLIPBOARD_STATE\" = sensitive ] && exit 0; cat; printf '\\0'"]
        running: true
        stdout: SplitParser {
            splitMarker: "\u0000"
            onRead: data => root._capture(data)
        }
        // wl-paste itself only exits if it crashes or the compositor lacks
        // the wlroots data-control protocol — back off instead of hot-
        // looping a binary that may simply be missing.
        onExited: exitCode => restartTimer.restart()
    }

    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: watcher.running = true
    }
}

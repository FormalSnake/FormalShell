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
//
// Images (M14 Task 6) ride a SECOND, independent `wl-paste --type image/png
// --watch` process — a separate Process/handler rather than in-band tagging
// alongside the text watcher's own stream. Its spawned script skips
// sensitive captures the same way, streams stdin to a mktemp file under
// `_imagesDir`, content-addresses it to `<sha256>.png` (an existing hash
// drops the temp and reuses the file — the same file IS the same capture),
// and NUL-delimits the final path on stdout, exactly like the text watcher's
// own entries. `copy()` branches on `entry.kind`: image entries `wl-copy
// --type image/png` the file back rather than re-emitting text. Eviction
// (overflow/remove/clear) can orphan an image file — history.js reports
// those paths back as `removedPaths`, and `_deletePaths` is the one place
// that ever calls `rm`, guarded to paths under `_imagesDir` only.
Singleton {
    id: root

    readonly property string _stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/formalshell";
    }

    readonly property string _imagesDir: root._stateDir + "/clipboard-images"

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
        root._deletePaths(result.removedPaths);
    }

    function _captureImage(path) {
        var result = History.add({ items: root.items }, { id: root._nextId(), kind: "image", path: path }, Date.now());
        if (result.state.items !== root.items)
            adapter.items = result.state.items;
        root._deletePaths(result.removedPaths);
    }

    function copy(id) {
        var entry = root.items.find(function (i) { return i.id === id; });
        if (!entry)
            return;
        if (entry.kind === "image")
            copyProc.exec({ command: ["sh", "-c", 'exec wl-copy --type image/png < "$0"', entry.path] });
        else
            copyProc.exec({ command: ["wl-copy", entry.text] });
    }

    function remove(id) {
        var result = History.remove({ items: root.items }, id);
        if (result.state.items !== root.items)
            adapter.items = result.state.items;
        root._deletePaths(result.removedPaths);
    }

    function clear() {
        var result = History.clear({ items: root.items });
        if (result.state.items !== root.items)
            adapter.items = result.state.items;
        root._deletePaths(result.removedPaths);
    }

    // The one place that ever calls `rm` — every path is checked against
    // `_imagesDir` first so an eviction can never delete anything outside
    // the content-addressed image store, no matter what history.js reports.
    function _deletePaths(paths) {
        var safe = (paths || []).filter(function (p) { return p.indexOf(root._imagesDir + "/") === 0; });
        if (safe.length === 0)
            return;
        deleteProc.exec({ command: ["rm", "-f", "--"].concat(safe) });
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

    Process {
        id: deleteProc
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

    // Second, independent watcher for image/png captures (see header
    // comment). wl-paste execs "sh" "-c" "<script>" "<_imagesDir>" per
    // change, so the trailing command-array argument lands in the script's
    // own $0 — the same idiom `copy()`'s wl-copy-back one-liner uses above.
    // A zero-byte read (an empty selection, e.g. a clear) leaves no file
    // behind; a hash collision with an already-captured image drops the
    // fresh temp file and reuses the existing one.
    Process {
        id: imageWatcher
        command: ["wl-paste", "--type", "image/png", "--watch", "sh", "-c",
            "[ \"$CLIPBOARD_STATE\" = sensitive ] && exit 0; " +
            "dir=\"$0\"; mkdir -p \"$dir\" || exit 0; " +
            "tmp=$(mktemp \"$dir/tmp.XXXXXX\") || exit 0; cat > \"$tmp\"; " +
            "if [ ! -s \"$tmp\" ]; then rm -f \"$tmp\"; exit 0; fi; " +
            "hash=$(sha256sum \"$tmp\" | cut -d ' ' -f1); file=\"$dir/$hash.png\"; " +
            "if [ -e \"$file\" ]; then rm -f \"$tmp\"; else mv \"$tmp\" \"$file\"; fi; " +
            "printf '%s\\0' \"$file\"",
            root._imagesDir]
        running: true
        stdout: SplitParser {
            splitMarker: "\u0000"
            onRead: data => root._captureImage(data)
        }
        onExited: exitCode => imageRestartTimer.restart()
    }

    Timer {
        id: imageRestartTimer
        interval: 3000
        onTriggered: imageWatcher.running = true
    }
}

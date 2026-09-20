pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../Clipboard/history.js" as History
import "../Clipboard/urilist.js" as UriList
import "../Core/proc.js" as Proc

// Capture via `wl-paste --type text --watch <cmd>` under a long-running
// Process (verified against the wl-clipboard 2.3.0 man page in the store):
// wl-paste forks <cmd> on every clipboard change, connects its stdin to the
// new selection, and sets CLIPBOARD_STATE in its environment (`data` | `nil`
// | `clear` | `sensitive`, `sensitive` is the one wl-paste itself derives
// from an `x-kde-passwordManagerHint` mime, the cheap password-manager
// signal the plan asks for). The spawned shell one-liner below skips
// forwarding sensitive captures at all; nil/clear captures still reach
// history.js's sanitize() as empty text and are dropped there. Entries are
// NUL-delimited on stdout (clipboard text can itself contain newlines) and
// split with a SplitParser whose marker is the NUL character above.
//
// History persists to $XDG_STATE_HOME/formalshell/clipboard.json via the
// same FileView+JsonAdapter pattern Core/State.qml uses for state.json,
// this file is its own, separate from state.json, per the plan's Task 2.
//
// Images (M14 Task 6) ride a SECOND, independent `wl-paste --type image/png
// --watch` process, a separate Process/handler rather than in-band tagging
// alongside the text watcher's own stream. Its spawned script skips
// sensitive captures the same way, streams stdin to a mktemp file under
// `_imagesDir`, content-addresses it to `<sha256>.png` (an existing hash
// drops the temp and reuses the file, the same file IS the same capture),
// and NUL-delimits the final path on stdout, exactly like the text watcher's
// own entries. `copy()` branches on `entry.kind`: image entries `wl-copy
// --type image/png` the file back rather than re-emitting text. Eviction
// (overflow/remove/clear) can orphan an image file, history.js reports
// those paths back as `removedPaths`, and `_deletePaths` is the one place
// that ever calls `rm`, guarded to paths under `_imagesDir` only.
//
// A THIRD watcher takes `text/uri-list`, which is how a GTK4 app copies an
// image: Loupe and Nautilus offer the file, never its pixels, so the
// image/png watcher above does not fire for them at all. urilist.js reads
// the offer down to one local picture, `importProc` brings it into the same
// store (a png copied as is, anything else through ffmpeg, so every file in
// the store stays a png and `copy()` and clipssh need no second branch),
// and the path the text watcher recorded for the same copy is dropped as
// the echo it is. No ffmpeg, or a file it cannot decode, leaves that text
// row as the honest record of the copy.
Singleton {
    id: root

    readonly property string _stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/formalshell";
    }

    readonly property string _imagesDir: root._stateDir + "/clipboard-images"

    // The store's own half of a capture, run with the bytes already in
    // `$tmp` under `$dir`: an empty read leaves nothing behind, the file is
    // named by its sha256, and the final path goes out NUL-delimited.
    readonly property string _storeScript:
        "if [ ! -s \"$tmp\" ]; then rm -f \"$tmp\"; exit 0; fi; " +
        "hash=$(sha256sum \"$tmp\" | cut -d ' ' -f1); file=\"$dir/$hash.png\"; " +
        "if [ -e \"$file\" ]; then rm -f \"$tmp\"; else mv \"$tmp\" \"$file\"; fi; " +
        "printf '%s\\0' \"$file\""

    property alias items: adapter.items

    property int _idSeq: 0
    function _nextId() {
        root._idSeq += 1;
        return Date.now() + "-" + root._idSeq;
    }

    // Burst coalescing, the floor an event-driven watcher does not get for
    // free. Maccy and Raycast sample the pasteboard on a timer, so an app
    // that rewrites the clipboard once per keystroke can still only leave
    // one row per tick; `wl-paste --watch` forks per change instead, and one
    // such app turned this whole 300-entry ledger over in two seconds (76
    // rows, one per distinct character it wrote). A text capture waits
    // `_settleMs` and a newer one inside that window replaces it, so only
    // the value the clipboard settles on is recorded. Images capture
    // immediately: their path already costs a sha256 over the bytes.
    readonly property int _settleMs: 300

    property string _pendingText
    property bool _hasPendingText: false

    function _capture(text) {
        root._pendingText = text;
        root._hasPendingText = true;
        settleTimer.restart();
    }

    function _commitText() {
        if (!root._hasPendingText)
            return;
        root._hasPendingText = false;
        var result = History.add({ items: root.items }, { id: root._nextId(), text: root._pendingText }, Date.now());
        if (result.state.items !== root.items)
            adapter.items = result.state.items;
        root._deletePaths(result.removedPaths);
    }

    function _captureImage(path) {
        var result = History.add({ items: root.items }, { id: root._nextId(), kind: "image", path: path }, Date.now());
        if (result.state.items !== root.items)
            adapter.items = result.state.items;
        root._deletePaths(result.removedPaths);
        // `clipssh.autoSendImages`, off by default. Here rather than in
        // ClipsshService listening to `items`: an image re-copied from
        // history moves an existing entry to the front instead of appending
        // one, so a list watcher would miss exactly the copies that matter.
        // The service owns the gate; this is only the moment.
        ClipsshService.autoSendImage(path);
    }

    // The text watcher sees the same file copy as its path (or its uri, for
    // a file GTK cannot name by path), before or after the import lands.
    readonly property int _echoMs: 5000

    function _captureUriList(data) {
        var file = UriList.imageFile(data);
        if (!file)
            return;
        importProc.source = file;
        importProc.exec({ command: ["sh", "-c",
            "dir=\"$0\"; src=\"$1\"; [ -f \"$src\" ] || exit 0; mkdir -p \"$dir\" || exit 0; " +
            "tmp=$(mktemp \"$dir/tmp.XXXXXX\") || exit 0; " +
            "if [ \"$2\" = png ]; then cp -- \"$src\" \"$tmp\"; " +
            "else ffmpeg -v error -y -i \"$src\" -frames:v 1 -update 1 -c:v png -f image2 \"$tmp\"; fi " +
            "|| { rm -f \"$tmp\"; exit 0; }; " + root._storeScript,
            root._imagesDir, file.path, file.png ? "png" : "convert"] });
    }

    function _captureImported(path, source) {
        var echoes = [source.path, source.uri];
        if (root._hasPendingText && echoes.indexOf(root._pendingText.replace(/\0/g, "").trim()) >= 0) {
            settleTimer.stop();
            root._hasPendingText = false;
        }
        var state = History.dropEcho({ items: root.items }, echoes, Date.now(), root._echoMs);
        if (state.items !== root.items)
            adapter.items = state.items;
        root._captureImage(path);
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
        // A capture still inside its settle window belongs to the history
        // being cleared, not to the one after it.
        settleTimer.stop();
        root._hasPendingText = false;
        var result = History.clear({ items: root.items });
        if (result.state.items !== root.items)
            adapter.items = result.state.items;
        root._deletePaths(result.removedPaths);
    }

    // The one place that ever calls `rm`, every path is checked against
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
    // the entry boundary, skipped entirely (no NUL emitted either) when
    // CLIPBOARD_STATE says the selection is a password-manager hint.
    Process {
        id: watcher
        command: Proc.dieWithParent(["wl-paste", "--type", "text", "--watch", "sh", "-c",
            "[ \"$CLIPBOARD_STATE\" = sensitive ] && exit 0; cat; printf '\\0'"])
        running: true
        stdout: SplitParser {
            splitMarker: "\u0000"
            onRead: data => root._capture(data)
        }
        // wl-paste itself only exits if it crashes or the compositor lacks
        // the wlroots data-control protocol, back off instead of hot-
        // looping a binary that may simply be missing.
        onExited: exitCode => restartTimer.restart()
    }

    Timer {
        id: settleTimer
        interval: root._settleMs
        onTriggered: root._commitText()
    }

    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: watcher.running = true
    }

    // Second, independent watcher for image/png captures (see header
    // comment). wl-paste execs "sh" "-c" "<script>" "<_imagesDir>" per
    // change, so the trailing command-array argument lands in the script's
    // own $0, the same idiom `copy()`'s wl-copy-back one-liner uses above.
    // A zero-byte read (an empty selection, e.g. a clear) leaves no file
    // behind; a hash collision with an already-captured image drops the
    // fresh temp file and reuses the existing one.
    Process {
        id: imageWatcher
        command: Proc.dieWithParent(["wl-paste", "--type", "image/png", "--watch", "sh", "-c",
            "[ \"$CLIPBOARD_STATE\" = sensitive ] && exit 0; " +
            "dir=\"$0\"; mkdir -p \"$dir\" || exit 0; " +
            "tmp=$(mktemp \"$dir/tmp.XXXXXX\") || exit 0; cat > \"$tmp\"; " +
            root._storeScript,
            root._imagesDir])
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

    // Third watcher, `text/uri-list` (see header comment). The offer is a
    // line or two of text, so it is forwarded whole and read in urilist.js
    // rather than parsed in sh.
    Process {
        id: uriWatcher
        command: Proc.dieWithParent(["wl-paste", "--type", "text/uri-list", "--watch", "sh", "-c",
            "[ \"$CLIPBOARD_STATE\" = sensitive ] && exit 0; cat; printf '\\0'"])
        running: true
        stdout: SplitParser {
            splitMarker: "\u0000"
            onRead: data => root._captureUriList(data)
        }
        onExited: exitCode => uriRestartTimer.restart()
    }

    Timer {
        id: uriRestartTimer
        interval: 3000
        onTriggered: uriWatcher.running = true
    }

    // One import at a time: a newer copy's exec() replaces a running one,
    // which is the right winner. `source` is the copy the running import
    // belongs to.
    Process {
        id: importProc
        property var source: null
        stdout: SplitParser {
            splitMarker: "\u0000"
            onRead: data => root._captureImported(data, importProc.source)
        }
    }
}

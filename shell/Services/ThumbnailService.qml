pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core
import "thumbnails.js" as Thumbs
import "../Menu/providers.js" as Providers

// Prerendered square thumbnails for the wallpaper picker's grid.
//
// The grid used to point every cell straight at the wallpaper itself and let
// Qt decode it down (Menu.qml's picker block, `sourceSize` capped at the
// cell). That bounds memory but not time: a directory of 4K/6K sources costs
// a full JPEG decode per cell on every open, which is the whole reason the
// route felt slow to enter. ffmpeg draws each one once into
// $XDG_CACHE_HOME/formalshell/thumbnails instead, and the grid decodes a
// 512px JPEG.
//
// "Prerendered" is the point: the warm runs a few seconds after startup off
// the configured picker.directory, so an ordinary session has the cache
// built long before the picker is ever summoned. Entering the route warms
// again with whatever the scan just found, which is what picks up a
// wallpaper added since, and the picker's `select` mode warms an arbitrary
// caller's directory the same way.
//
// Nothing here is load-bearing. thumbFor() answers "" for anything not yet
// on disk and the grid falls back to the source, so an install with no
// ffmpeg on PATH, a directory being warmed right now, and a format ffmpeg
// cannot decode all behave exactly as the picker did before this existed.
Singleton {
    id: root

    // The square edge of a cached thumbnail, in px. The grid's cells are
    // ~130px wide at the launcher's card width and it decodes at 2x for
    // hidpi, so 512 covers the largest cell any output asks for with room
    // over. It is part of every cache filename: raising it invalidates the
    // old files rather than silently reusing them at the wrong size.
    readonly property int size: 512

    // Four at once: the warm is background work competing with a session
    // that is doing something else, and ffmpeg saturates a core per job.
    readonly property int concurrency: 4

    readonly property string cacheDir: {
        const xdgCache = Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache");
        return xdgCache + "/formalshell/thumbnails";
    }

    // Source path -> true once its thumbnail is confirmed on disk. Replaced
    // wholesale rather than mutated so the grid's bindings re-fire; batched
    // through _flush below so a directory of a thousand files costs a
    // handful of reassignments instead of one per file.
    property var _ready: ({})
    property var _pending: []

    function pathFor(src) {
        return Thumbs.cachePath(root.cacheDir, src, root.size);
    }

    // "" means "not cached", which every caller has to treat as "draw the
    // source instead" rather than as an error.
    function thumbFor(src) {
        return root._ready[src] === true ? root.pathFor(src) : "";
    }

    function urlFor(src) {
        const p = root.thumbFor(src);
        return p === "" ? "" : "file://" + p;
    }

    function cachedCount(paths) {
        var n = 0;
        (paths || []).forEach(function (p) {
            if (root._ready[p] === true)
                n++;
        });
        return n;
    }

    // --- warming ---------------------------------------------------------

    // The listing a warm was asked for while one was already running. One
    // ffmpeg fleet at a time: the picker opening mid-warm must not stack a
    // second one on top, and the newer listing is the one worth building, so
    // the request is coalesced rather than queued.
    property var _queued: null

    function warm(paths) {
        if (!paths || paths.length === 0)
            return;
        if (warmProc.running) {
            root._queued = paths;
            return;
        }
        root._queued = null;
        warmProc.command = ["sh", "-c", Thumbs.warmScript(root.concurrency), "sh",
            root.cacheDir, String(root.size)].concat(Thumbs.warmArgs(root.cacheDir, paths, root.size));
        warmProc.running = true;
    }

    // The directory form, for the startup warm and for `picker select`'s
    // arbitrary directory: same scan the picker route itself runs, from the
    // one place that decides what counts as a pickable image.
    function warmDirectory(dir) {
        if (!dir || dir === "")
            return;
        scanProc.command = Providers.pickerScanCommand(dir);
        scanProc.running = true;
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: root.warm(text.split("\n").filter(function (l) { return l.length > 0; }))
        }
    }

    Process {
        id: warmProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.length > 0)
                    root._pending.push(data);
                flushTimer.start();
            }
        }
        // running is cleared by hand before the requeue: warm() refuses while
        // this process is running, and whether Quickshell has already dropped
        // the flag by the time it emits this is not a detail worth depending
        // on.
        onExited: {
            root._flush();
            const queued = root._queued;
            root._queued = null;
            warmProc.running = false;
            if (queued !== null)
                root.warm(queued);
        }
    }

    Timer {
        id: flushTimer
        interval: 80
        onTriggered: root._flush()
    }

    function _flush() {
        if (root._pending.length === 0)
            return;
        var next = {};
        for (var k in root._ready)
            next[k] = root._ready[k];
        root._pending.forEach(function (p) { next[p] = true; });
        root._pending = [];
        root._ready = next;
    }

    // --- startup ---------------------------------------------------------

    readonly property string _pickerDir: Core.Config.get("picker.directory", "")

    // Debounced rather than immediate, both on the way in and on a config
    // change: startup has a bar, a background and a theme to draw before a
    // cache nobody has asked for yet deserves any cores, and a settings.json
    // being edited fires this key repeatedly as the file is saved.
    Component.onCompleted: bootTimer.start()
    on_PickerDirChanged: bootTimer.restart()

    Timer {
        id: bootTimer
        interval: 3000
        onTriggered: root.warmDirectory(root._pickerDir)
    }
}

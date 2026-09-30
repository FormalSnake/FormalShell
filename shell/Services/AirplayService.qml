pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core
import "../Core/proc.js" as Proc
import "../Airplay/model.js" as AirplayModel

// AirPlay over UxPlay (M75 Task 6, plan at
// docs/superpowers/plans/2026-09-28-m75-iphone.md). Replaces the owner's
// hand-rolled `kyan.airplay` unit (g815, ~/.config/nix): the same fixed
// legacy ports (`-p`) and the same mirroring window (no `-vs 0`, the owner
// shares it in meetings), now behind `airplay.enable` and owned by the
// shell instead of a standalone systemd unit. nix/nixos-module.nix's
// `airplay.enable` opens those ports and turns on avahi publishing, so
// nothing here has to shell out to either.
//
// UxPlay has no MPRIS and no query verb of its own. `active` is read off
// whether the `-dacp` file exists (written exactly while a client is
// connected, removed on disconnect and on exit -- README and
// export_dacp()/conn_destroy(), read-reference only). Metadata and cover
// art are read off the `-md`/`-ca` files the same way, both parsed in
// shell/Airplay/model.js, whose header carries the exact write behaviour
// this reads against. Neither file's directory exists on its own; the
// shell creates it before uxplay ever runs.
//
// No transport control: UxPlay reports no play/pause state and takes no
// remote command of its own (the DACP export is for an external DACP
// client to *drive the phone*, and this shell has no DACP client). So this
// is a read-only media source -- MediaService leaves it out of every
// playback/volume ternary rather than fake a control that does nothing.
Singleton {
    id: root

    readonly property bool enabled: Core.Config.loaded && Core.Config.get("airplay.enable", false) === true
    readonly property string _configuredName: String(Core.Config.get("airplay.name", ""))

    readonly property string _runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/formalshell/airplay"
    readonly property string _metaPath: root._runtimeDir + "/meta"
    readonly property string _coverPath: root._runtimeDir + "/cover.jpg"
    readonly property string _dacpPath: root._runtimeDir + "/dacp"

    property bool installed: false
    property bool _dirReady: false
    property string _hostname: ""
    readonly property string name: AirplayModel.resolveName(root._configuredName, root._hostname)

    property bool running: false
    property bool active: false
    property string client: ""
    property string title: ""
    property string artist: ""
    property string album: ""
    property string genre: ""
    // The cover file's own mtime, read alongside its size: since UxPlay
    // overwrites the same path in place, the file:// URL string never
    // changes on its own, and an Image bound to an unchanged string never
    // reloads. Folding the mtime into the URL is what forces that reload
    // on a genuine new write, and gives it for free -- no separate counter
    // to keep in step.
    property bool hasCover: false
    property int _coverMtime: 0
    readonly property string coverUrl: root.hasCover ? "file://" + root._coverPath + "?" + root._coverMtime : ""
    property string lastError: ""

    readonly property bool _shouldRun: root.enabled && root.installed && root._dirReady

    // --- startup: runtime dir, hostname, PATH probe -----------------------

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root._runtimeDir]
        onExited: exitCode => root._dirReady = exitCode === 0
    }

    Process {
        id: hostnameProc
        command: ["hostname"]
        stdout: StdioCollector {
            onStreamFinished: root._hostname = text.trim()
        }
    }

    // 127 is "not on PATH", the one exit that means installed: false rather
    // than a uxplay that started and died.
    Process {
        id: probeProc
        command: ["sh", "-c", "command -v uxplay >/dev/null 2>&1"]
        onExited: exitCode => root.installed = exitCode === 0
    }

    Component.onCompleted: {
        mkdirProc.running = true;
        hostnameProc.running = true;
        probeProc.running = true;
        root._apply();
    }

    // --- the receiver -------------------------------------------------------

    readonly property int _baseBackoffMs: 2000
    readonly property int _maxBackoffMs: 60000
    property int _backoffMs: root._baseBackoffMs

    Process {
        id: uxplayProc
        command: Proc.dieWithParent(["uxplay", "-p", "-n", root.name, "-nh",
            "-md", root._metaPath, "-ca", root._coverPath, "-dacp", root._dacpPath])
        stdout: SplitParser {
            onRead: line => {
                var event = AirplayModel.parseLine(line);
                if (!event)
                    return;
                if (event.type === "connected") {
                    root.client = event.name;
                    root.lastError = "";
                } else if (event.type === "disconnected") {
                    root.client = "";
                } else if (event.type === "error") {
                    root.lastError = event.message;
                }
            }
        }
        onRunningChanged: {
            root.running = uxplayProc.running;
            if (!uxplayProc.running)
                root._reset();
        }
        onExited: exitCode => {
            if (root._shouldRun)
                retryTimer.start();
        }
    }

    Timer {
        id: retryTimer
        interval: root._backoffMs
        onTriggered: {
            root._backoffMs = Math.min(root._maxBackoffMs, root._backoffMs * 2);
            if (root._shouldRun)
                uxplayProc.running = true;
        }
    }

    function _reset() {
        root.active = false;
        root.client = "";
        root.title = "";
        root.artist = "";
        root.album = "";
        root.genre = "";
        root.hasCover = false;
        root._coverMtime = 0;
        root.lastError = "";
    }

    // Reads the three inputs directly rather than through `_shouldRun`:
    // this runs synchronously off `on_DirReadyChanged` and the other two
    // onXChanged handlers below, one of which is always the change that
    // triggered the call, and `_shouldRun`'s own binding does not reliably
    // observe that same change yet at this point in the engine's update
    // pass (confirmed live: `dirReady: true` alongside a stale `_shouldRun:
    // false`, which left `uxplayProc` never spawning at all). The two
    // Process callbacks below keep reading `_shouldRun`, since neither runs
    // inside the tick that changes it.
    function _apply() {
        if (root.enabled && root.installed && root._dirReady) {
            if (!uxplayProc.running && !retryTimer.running) {
                root._backoffMs = root._baseBackoffMs;
                uxplayProc.running = true;
            }
            return;
        }
        retryTimer.stop();
        uxplayProc.running = false;
    }

    onEnabledChanged: root._apply()
    onInstalledChanged: root._apply()
    on_DirReadyChanged: root._apply()

    // --- dacp presence (`active`) -------------------------------------------

    // Same "watch a file that may not exist yet, poll until it does"
    // idiom AirpodsBackend's status.json watch uses: the dacp path's parent
    // exists (mkdirProc above), but the file itself only appears for as
    // long as a client is connected, so FileNotFound is the ordinary idle
    // state here, not a startup race to wait out once.
    FileView {
        id: dacpFile
        path: root._dacpPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.active = true;
            dacpRewatch.stop();
        }
        onLoadFailed: error => {
            root.active = false;
            if (error === FileViewError.FileNotFound && uxplayProc.running)
                dacpRewatch.restart();
        }
    }

    Timer {
        id: dacpRewatch
        interval: 500
        onTriggered: dacpFile.reload()
    }

    onRunningChanged: {
        if (root.running)
            dacpFile.reload();
        else
            dacpRewatch.stop();
    }

    // --- metadata -----------------------------------------------------------

    FileView {
        id: metaFile
        path: root._metaPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var m = AirplayModel.parseMetadata(metaFile.text());
            root.title = m.title;
            root.artist = m.artist;
            root.album = m.album;
            root.genre = m.genre;
        }
        onLoadFailed: error => {
            root.title = "";
            root.artist = "";
            root.album = "";
            root.genre = "";
        }
    }

    // --- cover art ------------------------------------------------------------
    //
    // FileView is a text reader; the cover is a JPEG (or, for the reset
    // placeholder, a PNG), so this only ever asks the filesystem for its
    // size and mtime, never its content. Polled rather than watched: a
    // JPEG write can span several inotify events before write_coverart()'s
    // single fwrite() finishes, and a poll settled on the file's own stat
    // is simpler than debouncing those.
    //
    // UxPlay never proactively clears `-md`/`-ca` on disconnect (only the
    // *next* connect's format negotiation resets them), so `active` going
    // false clears the displayed fields here rather than leaving the last
    // session's track on screen.
    onActiveChanged: {
        if (root.active)
            coverStatProc.running = true;
        else
            root._reset();
    }

    Timer {
        id: coverPoll
        interval: 800
        repeat: true
        running: root.active
        onTriggered: coverStatProc.running = true
    }

    Process {
        id: coverStatProc
        command: ["sh", "-c", 'stat -c "%s %Y" "$1" 2>/dev/null || echo "-1 0"', "sh", root._coverPath]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.trim().split(" ");
                var size = parseInt(parts[0], 10);
                var mtime = parseInt(parts[1], 10);
                var real = isFinite(size) && size > 0 && !AirplayModel.isPlaceholderCover(size);
                root.hasCover = real;
                root._coverMtime = real && isFinite(mtime) ? mtime : 0;
            }
        }
    }
}

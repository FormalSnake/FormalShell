pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Notifications
import "../Localsend/model.js" as LocalsendModel
import "../Core/proc.js" as Proc

// LocalSend over 0w0mewo/localsend-cli (M75 Task 5, plan at
// docs/superpowers/plans/2026-09-28-m75-iphone.md), picked over the official
// Rust `cli/` crate for the reasons nix/localsend-cli.nix's header records:
// this is the only one with `scan`, `send`, and an unattended `recv`.
//
// Interop check (a), read from the CLI's own source at 7865fb1c: `recv`
// defaults `--https` to true (cmd/recv/recv.go) and so does `send`
// (cmd/send/send.go), both generating a throwaway self-signed cert
// (LoadOrGenTempTLScert) the same way the official app's own HTTPS mode
// does, fingerprint-pinned per the protocol's §2. So the receiver below is
// run with no `--https` flag at all -- the default is already the mode the
// iPhone's own default HTTPS advertisement expects, and passing
// `--https=false` would be the thing that breaks interop, not fix it.
//
// Interop check (b): a LocalSend v2 "text message" is not a metadata-only
// shortcut. localsend/protocol's README (§4.1) shows `preview` as a
// nullable convenience field on the file entry, but the actual content
// still always travels through the ordinary §4.2 upload POST, same as any
// file. This CLI's FileMeta (internal/models/filemeta.go) has no `preview`
// field at all and doesn't need one: `preUploadHandler` accepts the
// metadata (silently dropping the unknown key), and the sender's real
// upload lands and gets written to `saveToDir` as an ordinary small text
// file, same as any other. Nothing is dropped, so a phone-sent text message
// needs no special case here: the directory watch below already toasts it
// like any other received file.
//
// The toast comes from watching the receive directory for a filename that
// wasn't there last poll rather than from `recv`'s `Recv file file=<name>`
// log line, so the Open action points at what actually landed on disk.
Singleton {
    id: root

    readonly property bool receiveEnabled: Config.loaded && Config.get("localsend.receive", false) === true
    readonly property string alias: {
        var a = String(Config.get("localsend.alias", ""));
        return a !== "" ? a : (root._hostname !== "" ? root._hostname : "FormalShell");
    }
    readonly property string dir: {
        var d = String(Config.get("localsend.dir", ""));
        return d !== "" ? d : (Quickshell.env("HOME") + "/Downloads");
    }

    readonly property string _runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/formalshell"

    // --- presence and receiver state ----------------------------------------

    property bool installed: false
    property bool receiving: false
    property string lastError: ""
    property string _hostname: ""

    readonly property bool _shouldReceive: root.receiveEnabled && root.installed

    // --- peers ---------------------------------------------------------------

    property var peers: []
    property bool scanning: false
    property double lastScanAt: 0
    // A scan this fresh is still trusted rather than re-run, so opening the
    // launcher twice in a row doesn't cost a second 4s wait.
    readonly property int _scanFreshMs: 20000

    // --- send ------------------------------------------------------------------

    property string sendTarget: ""
    readonly property bool busy: sendProc.running

    // --- public verbs --------------------------------------------------------

    // `force` skips the freshness cache -- the menu's own retry action.
    function scan(force) {
        if (!root.installed || root.scanning)
            return;
        if (!force && root.peers.length > 0 && (Date.now() - root.lastScanAt) < root._scanFreshMs)
            return;
        root.scanning = true;
        scanProc.command = ["localsend-cli", "scan", "-t", "4"];
        scanProc.running = true;
    }

    // `peer` is the device's advertised alias, resolved against the last
    // scan; `paths` is one or more files (or directories, the CLI recurses).
    // Answers whether a send was actually started.
    function send(peer, paths) {
        var target = LocalsendModel.resolvePeer(root.peers, peer);
        if (!target) {
            NotificationService.notify("LOCALSEND FAILED", "'" + peer + "' is not in the last scan, rescan and try again", 2);
            return false;
        }
        root._sendPaths(target, paths);
        return true;
    }

    // The launcher's own dispatch (Menu.qml's "@ipc:localsend.send:<peer
    // index>:<clipboard entry id>"): the peer index is into the SAME peers
    // array the tree was built from, safe because nothing but a fresh scan
    // ever reorders it, and a fresh scan can't land between a row's build
    // and its own activation inside one launcher session.
    function sendClipboardEntryAt(peerIndex, entryId) {
        var peer = root.peers[peerIndex];
        if (!peer) {
            NotificationService.notify("LOCALSEND FAILED", "That device is no longer in range, rescan and try again", 2);
            return;
        }
        var entry = (ClipboardService.items || []).find(function (i) { return i.id === entryId; });
        if (!entry)
            return;
        if (entry.kind === "image") {
            root._sendPaths(peer, [entry.path]);
            return;
        }
        root._pendingTextPeer = peer;
        root._pendingTextPath = root._runtimeDir + "/localsend-text-" + Date.now() + ".txt";
        textWriteProc.command = ["sh", "-c",
            'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", root._pendingTextPath, entry.text];
        textWriteProc.running = true;
    }

    property var _pendingTextPeer: null
    property string _pendingTextPath: ""

    Process {
        id: textWriteProc
        onExited: exitCode => {
            if (exitCode === 0 && root._pendingTextPeer)
                root._sendPaths(root._pendingTextPeer, [root._pendingTextPath]);
            else
                NotificationService.notify("LOCALSEND FAILED", "Could not stage the clipboard text to send", 2);
            root._pendingTextPeer = null;
        }
    }

    // The capture flow's "Send to phone" action (ScreenshotIpc): the
    // paired iPhone's own device name among the last scan's peers when
    // IphoneService is connected, otherwise the first peer that scan found
    // -- "most recent" only in the sense that it's the one and only scan on
    // record, `scan`'s own Go map iteration carries no order promise beyond
    // that. "" when nothing is in range at all.
    function resolveSendTarget() {
        if (root.peers.length === 0)
            return "";
        if (IphoneService.connected && IphoneService.deviceName !== ""
                && LocalsendModel.resolvePeer(root.peers, IphoneService.deviceName))
            return IphoneService.deviceName;
        return root.peers[0].name;
    }

    function _sendPaths(peer, paths) {
        if (root.busy) {
            NotificationService.notify("LOCALSEND BUSY", "Still sending to " + root.sendTarget, 1);
            return;
        }
        root.sendTarget = peer.name;
        var argv = ["localsend-cli", "send", "--ip", peer.ip];
        (paths || []).forEach(function (p) { argv.push("-f", p); });
        sendProc.command = argv;
        sendProc.running = true;
        NotificationService.notify("LOCALSEND SENDING", (paths.length === 1 ? "1 item" : paths.length + " items") + " to " + peer.name, 1);
    }

    Process {
        id: sendProc
        stderr: StdioCollector {
            id: sendStderr
        }
        onExited: exitCode => {
            var outcome = LocalsendModel.sendOutcome(exitCode, sendStderr.text);
            if (outcome.ok) {
                NotificationService.notify("LOCALSEND SENT", "Delivered to " + root.sendTarget, 1);
            } else {
                var reason = outcome.failed.length > 0
                    ? outcome.failed[0].error || outcome.failed[0].msg
                    : "localsend-cli exited " + exitCode;
                root.lastError = reason;
                NotificationService.notify("LOCALSEND FAILED", root.sendTarget + ": " + reason, 2);
            }
            root.sendTarget = "";
        }
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            id: scanStdout
        }
        onExited: exitCode => {
            root.peers = LocalsendModel.parseScan(scanStdout.text);
            root.lastScanAt = Date.now();
            root.scanning = false;
        }
    }

    // --- receiver --------------------------------------------------------------

    readonly property int _baseBackoffMs: 2000
    readonly property int _maxBackoffMs: 30000
    property int _backoffMs: root._baseBackoffMs

    // No `--https=false`, no `-p`: see the header for why the default HTTPS
    // mode is the one that has to run for the phone's own default to reach
    // it, and no PIN key exists in settings.json for this feature.
    Process {
        id: recvProc
        command: Proc.dieWithParent(["localsend-cli", "recv", "-n", root.alias, "-d", root.dir])
        stderr: SplitParser {
            onRead: line => {
                var event = LocalsendModel.parseRecvLine(line);
                if (event && event.type === "error")
                    root.lastError = event.message;
            }
        }
        onRunningChanged: root.receiving = recvProc.running
        onExited: exitCode => {
            if (root._shouldReceive)
                retryTimer.start();
        }
    }

    Timer {
        id: retryTimer
        interval: root._backoffMs
        onTriggered: {
            root._backoffMs = Math.min(root._maxBackoffMs, root._backoffMs * 2);
            if (root._shouldReceive)
                recvProc.running = true;
        }
    }

    function _applyReceive() {
        if (root._shouldReceive) {
            if (!recvProc.running && !retryTimer.running) {
                root._backoffMs = root._baseBackoffMs;
                recvProc.running = true;
            }
            root._knownFiles = null;
            watchTimer.start();
        } else {
            retryTimer.stop();
            recvProc.running = false;
            watchTimer.stop();
            root._knownFiles = null;
        }
    }

    on_ShouldReceiveChanged: root._applyReceive()

    // --- receive directory watch ----------------------------------------------

    // null means "not primed yet": the first listing after the watch
    // (re)starts seeds the known set silently, so a file already sitting in
    // the directory before this session never reads as freshly received.
    property var _knownFiles: null

    // Started/stopped from _applyReceive() rather than bound to
    // `running`, since Timer.stop() on a running property with a live
    // binding would silence the binding for good, the same start/stop
    // shape retryTimer above already uses.
    Timer {
        id: watchTimer
        interval: 2000
        repeat: true
        onTriggered: watchProc.running = true
    }

    Process {
        id: watchProc
        command: ["sh", "-c", 'find "$1" -maxdepth 1 -type f -printf "%f\\n" 2>/dev/null', "sh", root.dir]
        stdout: StdioCollector {
            id: watchStdout
            onStreamFinished: {
                var names = watchStdout.text.split("\n").filter(function (n) { return n !== ""; });
                if (root._knownFiles !== null) {
                    LocalsendModel.newFiles(root._knownFiles, names).forEach(function (n) {
                        root._announce(n);
                    });
                }
                root._knownFiles = names;
            }
        }
    }

    function _announce(name) {
        var path = root.dir + "/" + name;
        NotificationService.notify("LOCALSEND RECEIVED", name, 1, [
            { key: "open", label: "Open", invoke: () => root._launch([path]) },
            { key: "reveal", label: "Show in Folder", invoke: () => root._launch([root.dir]) }
        ], path);
    }

    function _launch(argv) {
        launchProc.command = ["xdg-open"].concat(argv);
        launchProc.running = true;
    }

    Process {
        id: launchProc
    }

    // --- startup ---------------------------------------------------------------

    Process {
        id: hostnameProc
        command: ["hostname"]
        stdout: StdioCollector {
            onStreamFinished: root._hostname = text.trim()
        }
    }

    // 127 is "not on PATH"; anything else is a genuine presence, whether
    // the probe itself printed the version or errored on bad args.
    Process {
        id: probeProc
        command: ["sh", "-c", "command -v localsend-cli >/dev/null 2>&1"]
        onExited: exitCode => {
            root.installed = exitCode === 0;
            root._applyReceive();
        }
    }

    Component.onCompleted: {
        hostnameProc.running = true;
        probeProc.running = true;
    }
}

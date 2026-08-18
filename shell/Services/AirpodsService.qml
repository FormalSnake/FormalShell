pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../Airpods/model.js" as AirpodsModel

// Bridge to the omarchy-pods librepods daemon (M29 Task 1, plan at
// docs/superpowers/plans/2026-08-18-m29-device-panels.md). The daemon
// (github.com/thisisgm/omarchy-pods, `daemon/` subtree, GPL-3.0, built and
// run out-of-repo per SWITCHOVER.md) writes its whole state as one line of
// sorted-key JSON to $XDG_STATE_HOME/librepods/status.json via QSaveFile
// (never half-written), write-on-change only, and removes the file on
// quit — an absent file is the only "daemon down" signal there is, so this
// needs no separate liveness probe. AirpodsModel.parseStatus() already
// returns a complete default shape on every unusable path (missing file,
// malformed JSON, a schema_version this parser doesn't understand), which
// is what `available` below gates on.
//
// Control verbs go out over $XDG_RUNTIME_DIR/librepods.sock as one raw
// write, no framing, no reply expected (only the "status"/"reopen" verbs
// get one, and this service never sends either). Every send opens its own
// self-destroying Socket rather than reusing one — the same shape
// LibrePodsService.qml used against the old stock librepods app, and for
// the same reason: a shared long-lived Socket's errorOccurred leaves the
// underlying QLocalSocket non-null with no matching connectionStateChanged
// (pinned quickshell source, src/io/socket.cpp), which could wedge a
// reused Socket against future connect attempts after a single failed one.
Singleton {
    id: root

    readonly property string _stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/librepods";
    }

    // Empty XDG_RUNTIME_DIR means no socket and no fallback — the daemon's
    // own ipcpath.hpp refuses to guess one, and this mirrors that.
    readonly property string _runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string socketPath: root._runtimeDir === "" ? "" : root._runtimeDir + "/librepods.sock"

    property bool available: false
    property var status: AirpodsModel.parseStatus("")

    // Rewatch runs only while a consumer is registered — the bar widget,
    // for as long as it exists at all (opted into bar.layout), and the
    // panel, for as long as it's open — the same acquire()/release() shape
    // DualsenseService uses. Unlike settings.json/theme.json, whose
    // Config.qml/Theme.qml precedent this used to cite, status.json's
    // parent directory is created by the daemon itself and, on the common
    // daemonless host, never appears at all: an unconditional retry here
    // ran a FileView reload every 300ms for the shell's entire lifetime
    // even with zero consumers (AirpodsPanel is instantiated unconditionally
    // in shell.qml). Gating on refcount makes that cost genuinely zero on a
    // host that never opts in, and only as long as it takes the daemon to
    // start on one that does.
    property int _refCount: 0

    function acquire() {
        root._refCount++;
        if (root._refCount === 1)
            statusFile.reload();
    }

    function release() {
        root._refCount = Math.max(0, root._refCount - 1);
        if (root._refCount === 0)
            rewatchTimer.stop();
    }

    Timer {
        id: rewatchTimer
        interval: 300
        onTriggered: statusFile.reload()
    }

    FileView {
        id: statusFile
        path: root._stateDir + "/status.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._applyStatus()
        onLoadFailed: error => {
            // Only touch status/available on an actual transition. The
            // rewatch loop below can re-fire this handler every 300ms for
            // as long as a consumer is registered and no daemon is
            // running, and reassigning a fresh parseStatus() object on
            // every miss fired statusChanged on every tick, re-evaluating
            // every AirpodsPanel binding with nothing actually available
            // to show.
            if (root.available) {
                root.status = AirpodsModel.parseStatus("");
                root.available = false;
            }
            if (error === FileViewError.FileNotFound && root._refCount > 0)
                rewatchTimer.restart();
        }
    }

    function _applyStatus() {
        var parsed = AirpodsModel.parseStatus(statusFile.text());
        root.status = parsed;
        root.available = parsed.ok;
    }

    // Exact wire verbs the daemon's control socket understands
    // (daemon/librepods-ctl.cpp's usage text, read-reference only).
    // connect/disconnect/forget are deliberately excluded — those shell
    // out to bluetoothctl, and that job belongs to the Bluetooth panel.
    readonly property var _allowedVerbs: [
        "noise:off", "noise:anc", "noise:transparency", "noise:adaptive",
        "ca:on", "ca:off",
        "onebud:on", "onebud:off",
        "ear:one", "ear:both", "ear:off"
    ]

    function _isAllowed(verb) {
        if (root._allowedVerbs.indexOf(verb) !== -1)
            return true;
        return /^adaptive:(100|[0-9]{1,2})$/.test(verb);
    }

    Component {
        id: _sendComponent
        Socket {
            id: s
            property string message: ""
            onConnectionStateChanged: {
                if (s.connected) {
                    s.write(s.message);
                    s.flush();
                    s.connected = false;
                } else {
                    s.destroy();
                }
            }
            onError: error => s.destroy();
        }
    }

    // verb: a raw wire command, checked against _isAllowed before the
    // socket ever opens — an unknown verb or an unset XDG_RUNTIME_DIR is
    // refused right here, never sent. Returns whether the send was
    // attempted; the daemon gives no reply either way for a control verb.
    function send(verb) {
        if (root.socketPath === "" || !root._isAllowed(verb))
            return false;
        var s = _sendComponent.createObject(root, { message: verb });
        s.path = root.socketPath;
        s.connected = true;
        return true;
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import "../../Earbuds/airpods.js" as Airpods

// AirPods behind the earbuds backend contract (EarbudsService.qml's header),
// over the omarchy-pods librepods daemon (github.com/thisisgm/omarchy-pods,
// `daemon/` subtree, GPL-3.0, built and run out-of-repo per SWITCHOVER.md).
// The daemon writes its whole state as one line of sorted-key JSON to
// $XDG_STATE_HOME/librepods/status.json via QSaveFile (never half-written),
// write-on-change only, and removes the file on quit: an absent file is the
// only "daemon down" signal there is, so this needs no liveness probe.
//
// Control verbs go out over $XDG_RUNTIME_DIR/librepods.sock as one raw
// write, no framing, no reply expected. Every send opens its own
// self-destroying Socket rather than reusing one: a shared long-lived
// Socket's errorOccurred leaves the underlying QLocalSocket non-null with
// no matching connectionStateChanged (pinned quickshell source,
// src/io/socket.cpp), which could wedge a reused Socket against future
// connect attempts after a single failed one.
Scope {
    id: root

    readonly property string name: Airpods.BACKEND
    property bool available: false
    property var devices: []
    property var status: Airpods.parseStatus("")

    readonly property string _stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/librepods";
    }

    // Empty XDG_RUNTIME_DIR means no socket and no fallback, the daemon's
    // own ipcpath.hpp refuses to guess one, and this mirrors that.
    readonly property string _runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string socketPath: root._runtimeDir === "" ? "" : root._runtimeDir + "/librepods.sock"

    // status.json's parent directory is created by the daemon itself and,
    // on the common daemonless host, never appears at all, so the 300ms
    // rewatch runs only while held: an unconditional retry would reload a
    // FileView for the shell's whole lifetime with nobody looking.
    property bool _held: false

    function acquire() {
        root._held = true;
        statusFile.reload();
    }

    function release() {
        root._held = false;
        rewatchTimer.stop();
    }

    function set(deviceKey, controlKey, value) {
        if (deviceKey !== Airpods.BACKEND)
            return false;
        return root._send(Airpods.command(controlKey, value));
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
        onLoaded: root._apply(Airpods.parseStatus(statusFile.text()))
        onLoadFailed: error => {
            // Only on a transition: the rewatch re-fires this every 300ms
            // while no daemon runs, and a fresh object each miss would
            // re-evaluate every binding on the devices list for nothing.
            if (root.available)
                root._apply(Airpods.parseStatus(""));
            if (error === FileViewError.FileNotFound && root._held)
                rewatchTimer.restart();
        }
    }

    function _apply(parsed) {
        root.status = parsed;
        root.available = parsed.ok;
        root.devices = Airpods.normalise(parsed);
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

    // verb: "" when Airpods.command() refused the control, which never
    // reaches the socket; nor does anything with XDG_RUNTIME_DIR unset.
    function _send(verb) {
        if (root.socketPath === "" || verb === "")
            return false;
        var s = _sendComponent.createObject(root, { message: verb });
        s.path = root.socketPath;
        s.connected = true;
        return true;
    }
}

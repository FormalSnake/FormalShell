import QtQuick
import Quickshell
import Quickshell.Io

// Single-instance takeover lock (post-M16 addendum, owner ask 2026-08-03:
// "i see two bars there has to be instance locking" — a rebuild+respawn had
// raced an old shell instance against a new one, each drawing its own bar).
//
// The lock is a fixed unix socket at $XDG_RUNTIME_DIR/formalshell/instance.sock
// — deliberately NOT derived from the nix store path the running shell was
// built from, because that path changes on every rebuild: two builds of "the
// same" shell would never recognize each other as one instance if the lock
// lived under a store-path-keyed name. $XDG_RUNTIME_DIR is stable across
// rebuilds within a login session, which is exactly the scope a "one shell
// per session" invariant needs.
//
// Takeover protocol, line-delimited over the socket:
//   - on accepting a connection, the listening (old) side writes
//     "formalshell <pid>\n"
//   - the connecting (new) side replies "takeover <pid>\n"
//   - the old side, on reading a "takeover" line, logs and calls Qt.quit()
//
// Every instance starts by connecting as a *client* to the fixed path. A
// live instance answers with the greeting; the new instance requests
// takeover and polls (bounded, ~2s) for that connection to drop before
// binding its own SocketServer at the same path. If nothing answers (no
// instance running, or a stale socket file left behind by a crash),
// Quickshell.Io.SocketServer's own enableServer() unconditionally unlinks
// any existing file at its path before listen() (verified against the
// pinned quickshell source, src/io/socket.cpp) — so a crash-orphaned socket
// file needs no special handling here, the same server.active = true bind
// path clears it either way.
//
// Binding is never fought over: if the bind still fails after a takeover
// handshake (e.g. a permissions problem), this logs a warning once and the
// shell keeps running without the lock rather than retrying in a loop.
Scope {
    id: root

    readonly property string _runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/formalshell"
    readonly property string socketPath: root._runtimeDir + "/instance.sock"
    readonly property bool active: server.active

    // Whether the initial probe's outcome (a live instance found, or none)
    // has already been acted on — guards against the probe's error/
    // disconnect signals double-firing the same decision.
    property bool _resolved: false

    function _log(line) {
        console.log("formalshell: instance lock —", line);
    }

    function _bind() {
        if (server.active)
            return;
        server.active = true;
        if (server.active)
            root._log("acquired at " + root.socketPath + " (pid " + Quickshell.processId + ")");
        else
            console.warn("formalshell: instance lock — bind failed, continuing without single-instance guarantee");
    }

    function _requestTakeover() {
        if (root._resolved)
            return;
        root._resolved = true;
        root._log("live instance found, requesting takeover");
        probe.write("takeover " + Quickshell.processId + "\n");
        probe.flush();
        pollTimer.waited = 0;
        pollTimer.start();
    }

    Component.onCompleted: mkdirProc.running = true

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root._runtimeDir]
        onExited: {
            probe.path = root.socketPath;
            probe.connected = true;
        }
    }

    // Bounded wait for the old instance's connection to drop once takeover
    // has been requested. Binds regardless once the bound is hit even if the
    // old side never confirmed — SocketServer's own unlink-then-listen is
    // safe to call whether or not the old process has actually exited yet.
    Timer {
        id: pollTimer
        interval: 100
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval;
            if (!probe.connected || waited >= 2000) {
                stop();
                probe.connected = false;
                root._bind();
            }
        }
    }

    // Client half: probes for a live instance at startup.
    Socket {
        id: probe
        connected: false
        parser: SplitParser {
            splitMarker: "\n"
            onRead: message => {
                if (message.indexOf("formalshell ") === 0)
                    root._requestTakeover();
            }
        }
        onConnectionStateChanged: {
            if (!probe.connected && !root._resolved) {
                // Connected then dropped before a greeting arrived, or never
                // connected at all — either way there's no live instance to
                // hand off to.
                root._resolved = true;
                root._bind();
            }
        }
        onError: error => {
            if (!root._resolved) {
                root._resolved = true;
                root._bind();
            }
        }
    }

    // Server half: answers future instances the same way this one was (or
    // wasn't) answered.
    SocketServer {
        id: server
        path: root.socketPath
        handler: Component {
            Socket {
                id: conn
                parser: SplitParser {
                    splitMarker: "\n"
                    onRead: message => {
                        if (message.indexOf("takeover") === 0) {
                            console.log("formalshell: instance lock — being replaced (" + message + "), quitting");
                            Qt.quit();
                        }
                    }
                }
                onConnectionStateChanged: {
                    if (conn.connected) {
                        conn.write("formalshell " + Quickshell.processId + "\n");
                        conn.flush();
                    }
                }
            }
        }
    }
}

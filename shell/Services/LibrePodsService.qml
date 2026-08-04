pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// LibrePods noise-control bridge (M17 Task 2, corrected scope — plan at
// docs/superpowers/plans/2026-08-04-m17-localsend-librepods.md). Upstream
// librepods (~/Developer/librepods, read-reference) ships no D-Bus surface
// at all on either branch — the Linux Qt app's only IPC is a QLocalServer
// named "app_server" (linux/main.cpp:1063-1066). Qt's local-socket backend
// resolves a bare name like that to a real filesystem socket under
// QDir::tempPath(), and the app's own single-instance cleanup hardcodes
// that resolved path as literally /tmp/app_server (main.cpp:1015), so this
// connects there directly rather than trusting tempPath() to agree with
// the app's own environment. The protocol is four write-only messages —
// noise:off|anc|transparency|adaptive (main.cpp:1092-1103) — battery and
// the active mode are never exported outside the GUI, so this service
// stores no state beyond `available` and never reads anything back.
//
// Every connection is one-shot: the app's own server disconnects the
// client right after handling a single message (main.cpp:1108), and a
// shared long-lived Socket's errorOccurred leaves its underlying
// QLocalSocket non-null with no matching connectionStateChanged (pinned
// quickshell source, src/io/socket.cpp), which could wedge a reused Socket
// against future connect attempts after a single failed probe. So `probe()`
// and `setNoise()` each spin up their own self-destroying Socket instance
// — the AppleMusicArtService `_procComponent` idiom, applied to sockets
// instead of processes — instead of sharing one.
//
// Probed only when the bluetooth panel opens (M16 Task 12's hidden-work
// rule: no poll loop, no standing subscription). The probe connection
// writes nothing at all, so it can never itself trigger the app's
// unrelated "reopen" single-instance behavior.
Singleton {
    id: root

    readonly property string socketPath: "/tmp/app_server"
    property bool available: false

    Component {
        id: _probeComponent
        Socket {
            id: s
            onConnectionStateChanged: {
                if (s.connected) {
                    root.available = true;
                    s.connected = false;
                } else {
                    s.destroy();
                }
            }
            onError: error => {
                root.available = false;
                s.destroy();
            }
        }
    }

    Component {
        id: _writeComponent
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

    function probe() {
        var s = _probeComponent.createObject(root);
        s.path = root.socketPath;
        s.connected = true;
    }

    // mode is one of "off"/"anc"/"transparency"/"adaptive" — verbatim
    // suffix of the wire message, never translated or validated beyond
    // what the four AIRPODS NOISE cells already constrain it to.
    function setNoise(mode) {
        if (!root.available)
            return;
        var s = _writeComponent.createObject(root, { message: "noise:" + mode });
        s.path = root.socketPath;
        s.connected = true;
    }
}

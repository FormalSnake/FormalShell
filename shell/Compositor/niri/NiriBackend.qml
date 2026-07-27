import QtQuick
import Quickshell
import Quickshell.Io

import "reducer.js" as Reducer

// Niri backend over niri's two-socket JSON IPC: the event-stream socket
// monopolizes its connection once activated ("EventStream" turns the
// connection one-way), so actions go out over a second, plain request
// socket. State is derived entirely by the pure reducer; this file only
// owns the sockets and normalizes the reducer's state onto the contract.
// Portions from DankMaterialShell (MIT, Copyright 2025 Avenge Media LLC).
Scope {
    id: root

    readonly property string socketPath: Quickshell.env("NIRI_SOCKET") ?? ""
    property var state: Reducer.initialState()

    readonly property bool available: eventSocket.connected && requestSocket.connected
    property var workspaces: state.workspaces
    property var windows: state.windows
    property var outputs: state.outputs
    property string focusedWindowId: state.focusedWindowId
    property string focusedWorkspaceId: state.focusedWorkspaceId
    property string focusedOutputName: state.focusedOutputName

    signal configReloaded(bool failed)

    function focusWorkspace(id) {
        requestSocket.request({ Action: { FocusWorkspace: { reference: { Id: Number(id) } } } });
    }
    function focusWindow(id) {
        requestSocket.request({ Action: { FocusWindow: { id: Number(id) } } });
    }
    function closeWindow(id) {
        requestSocket.request({ Action: { CloseWindow: { id: Number(id) } } });
    }
    function spawn(argv) {
        requestSocket.request({ Action: { Spawn: { command: argv } } });
    }
    function powerOffMonitors() {
        requestSocket.request({ Action: { PowerOffMonitors: {} } });
    }
    function powerOnMonitors() {
        requestSocket.request({ Action: { PowerOnMonitors: {} } });
    }
    // Reloads niri's current config file with no path argument (niri-ipc's
    // Action::LoadConfigFile { path: Option<String> }, verified against
    // niri-ipc/src/lib.rs and src/ipc/server.rs) — re-parses the `include`d
    // niri-border.kdl fragment ThemeEngine just wrote.
    function applyThemeFragment() {
        requestSocket.request({ Action: { LoadConfigFile: {} } });
    }

    function _connect() {
        if (root.socketPath === "")
            return;
        eventSocket.connected = true;
        requestSocket.connected = true;
    }

    Component.onCompleted: root._connect()

    Timer {
        id: reconnectTimer
        interval: 2000
        onTriggered: root._connect()
    }

    Socket {
        id: eventSocket
        path: root.socketPath

        onConnectionStateChanged: {
            if (connected) {
                write('"EventStream"\n');
                flush();
            } else {
                connected = false; // don't race Socket's own instant auto-reconnect; pace via reconnectTimer
                reconnectTimer.restart();
            }
        }

        onError: error => reconnectTimer.restart()

        parser: SplitParser {
            onRead: line => {
                var event;
                try {
                    event = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (event.Ok !== undefined || event.Err !== undefined)
                    return; // reply to the "EventStream" request itself, not an Event
                root.state = Reducer.reduce(root.state, event);
                if (event.ConfigLoaded !== undefined)
                    root.configReloaded(event.ConfigLoaded.failed);
            }
        }
    }

    Socket {
        id: requestSocket
        path: root.socketPath

        onConnectionStateChanged: {
            if (!connected) {
                connected = false;
                reconnectTimer.restart();
            }
        }

        onError: error => reconnectTimer.restart()

        function request(obj) {
            write(JSON.stringify(obj) + "\n");
            flush();
        }
    }
}

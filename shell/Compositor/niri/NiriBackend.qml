import QtQuick
import Quickshell
import Quickshell.Io

import "reducer.js" as Reducer
import "../park.js" as Park
import "../../Display/outputs.js" as Outputs

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
    // Re-derived when `outputs` lands as well as on every event: niri reports
    // window boxes relative to the workspace view, and only the output origin
    // turns those into the absolute logical coordinates `rect` promises.
    property var windows: Reducer.withAbsoluteRects(state.windows, state.workspaces, root.outputs)
    // Not reducer-derived, unlike everything else here: niri's event stream
    // carries no output event at all (niri-ipc's `Event` enum, lib.rs:1571),
    // so outputs only ever arrive as replies to an explicit Outputs request.
    property var outputs: []
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
    // niri-ipc/src/lib.rs and src/ipc/server.rs), re-parses the `include`d
    // niri-border.kdl fragment ThemeEngine just wrote.
    function applyThemeFragment() {
        requestSocket.request({ Action: { LoadConfigFile: {} } });
    }

    // Webcam overlay placement (M27 Task 5). MoveWindowToFloating rather than
    // ToggleWindowFloating (niri-ipc's other floating action) so a second call
    // on an already-floating window is a no-op instead of tiling it back.
    readonly property bool floatingPlacementAvailable: true

    function floatWindow(id) {
        requestSocket.request({ Action: { MoveWindowToFloating: { id: Number(id) } } });
    }

    // SizeChange::SetFixed/PositionChange::AdjustFixed are both logical
    // pixels (niri-ipc/src/lib.rs), but position is relative to the window's
    // own current spot, not absolute -- SetFixed's own offset is the
    // workspace's working-area origin, which this shell never queries. The
    // caller already guarantees `windows` carries a real `rect` for `id`
    // (BackendBase's contract), so reading it back here gives the delta to
    // the requested absolute (x, y) without needing that origin at all.
    function placeFloatingWindow(id, x, y, width, height) {
        const numId = Number(id);
        const w = Math.max(1, Math.round(width));
        const h = Math.max(1, Math.round(height));
        requestSocket.request({ Action: { SetWindowWidth: { id: numId, change: { SetFixed: w } } } });
        requestSocket.request({ Action: { SetWindowHeight: { id: numId, change: { SetFixed: h } } } });
        const current = root.windows.find(win => win.id === id);
        const pos = current && current.rect ? current.rect : { x: x, y: y };
        requestSocket.request({ Action: { MoveFloatingWindow: {
            id: numId,
            x: { AdjustFixed: x - pos.x },
            y: { AdjustFixed: y - pos.y }
        } } });
    }

    // Parking (M37). niri has no minimize, no scratchpad and no special
    // workspace, the full `niri msg action` list on 26.04 carries no hide
    // of any kind, so out of view means another workspace, with `focus`
    // false so the user stays where they are.
    readonly property bool windowParkingAvailable: true

    function parkWindow(id) {
        const target = Park.parkTarget(root.workspaces, root.windows,
            root.focusedWorkspaceId, root.focusedOutputName, id);
        if (target === "") {
            console.warn("NiriBackend: nowhere to park window", id);
            return;
        }
        requestSocket.request({ Action: { MoveWindowToWorkspace: {
            window_id: Number(id),
            reference: { Id: Number(target) },
            focus: false
        } } });
    }

    function unparkWindow(id) {
        if (root.focusedWorkspaceId === "")
            return;
        requestSocket.request({ Action: { MoveWindowToWorkspace: {
            window_id: Number(id),
            reference: { Id: Number(root.focusedWorkspaceId) },
            focus: false
        } } });
    }

    // Anywhere but the workspace being looked at. niri has no overlay
    // workspace, so "parked" and "on some other workspace" are the same fact
    // here, including a console the user scrolled away from, which the
    // toggle then brings back rather than hiding something already gone.
    function isWindowParked(id) {
        const win = root.windows.find(w => w.id === id);
        if (!win)
            return true;
        return win.workspaceId !== root.focusedWorkspaceId;
    }

    readonly property bool outputConfigAvailable: true
    // niri-ipc's OutputAction (lib.rs:1018) is Off/On/Mode/CustomMode/
    // Modeline/Scale/Transform/Position/Vrr, no mirror variant, because niri
    // has no mirroring primitive at all. setOutputMirror below is therefore a
    // declared no-op rather than a missing symbol, matching how
    // HyprlandBackend states applyThemeFragment's absence; the panel gates on
    // this flag and renders an honest unavailable cell.
    readonly property bool mirrorSupported: false

    // Output names are plain strings on the wire on both compositors, niri
    // keys its Outputs map by name, so none of the requests below carry the
    // Number(id) conversion the window/workspace actions above need.
    // Set across the request so the shared reply parser can attribute an Err
    // to this request rather than to one of the action acks that use the same
    // connection.
    property bool _outputsRequested: false

    function refreshOutputs() {
        root._outputsRequested = true;
        requestSocket.request("Outputs");
    }

    // No-op, matching BackendBase's contract default: `windows` here is
    // reduced from the event stream the socket already pushes, so it is never
    // behind in the way Hyprland's cached `j/clients` object is. Spelled out
    // rather than inherited because these backends duck-type the contract as
    // plain Scopes; BackendBase is the written contract and the null backend,
    // not a base type, so a caller reaching a function only defined there
    // would throw on whichever backend forgot it.
    function refreshWindows() {}

    function setOutputEnabled(name, enabled) {
        requestSocket.request({ Output: { output: name, action: enabled ? "On" : "Off" } });
        outputRefreshTimer.restart();
    }

    function setOutputScale(name, scale) {
        requestSocket.request({ Output: { output: name, action: { Scale: { scale: { Specific: scale } } } } });
        outputRefreshTimer.restart();
    }

    function setOutputMirror(name, sourceName) {} // see mirrorSupported above

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

    // niri applies an Output request from an idle callback (src/ipc/server.rs:415
    // schedules apply_transient_output_config), so its reply lands before the
    // change does, re-reading immediately would report the old geometry back.
    Timer {
        id: outputRefreshTimer
        interval: 300
        onTriggered: root.refreshOutputs()
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
                if (event.ConfigLoaded !== undefined) {
                    root.configReloaded(event.ConfigLoaded.failed);
                    // A reloaded config is the one thing that can change the
                    // output set without this shell having asked for it.
                    root.refreshOutputs();
                }
            }
        }
    }

    Socket {
        id: requestSocket
        path: root.socketPath

        onConnectionStateChanged: {
            if (connected) {
                root.refreshOutputs();
            } else {
                connected = false;
                reconnectTimer.restart();
            }
        }

        onError: error => reconnectTimer.restart()

        function request(obj) {
            write(JSON.stringify(obj) + "\n");
            flush();
        }

        // niri answers every request on this connection with exactly one
        // `Reply` line (src/ipc/server.rs:187's read/reply loop), so a plain
        // line parser correlates by shape: only an Ok(Outputs) reply carries
        // state, and Handled / OutputConfigChanged acks and Err strings alike
        // fall through untouched.
        parser: SplitParser {
            onRead: line => {
                var reply;
                try {
                    reply = JSON.parse(line);
                } catch (e) {
                    return;
                }
                // An Err reply to an Outputs request is a failed enumeration,
                // not an empty one, see BackendBase's outputsState comment for
                // why the panel must be able to tell those apart. Errs to other
                // requests are indistinguishable on this shared connection, so
                // only an outstanding Outputs request claims one.
                // Which request an Err answers is unknowable on this shared
                // connection, but the text niri sent back is not, and a
                // rejected action is otherwise a completely silent no-op.
                if (reply && reply.Err !== undefined)
                    console.warn("NiriBackend: niri rejected a request:", JSON.stringify(reply.Err));
                if (reply && reply.Err !== undefined && root._outputsRequested) {
                    root._outputsRequested = false;
                    root.outputs = [];
                    root.outputsState = "failed";
                    return;
                }
                if (!reply || !reply.Ok || reply.Ok.Outputs === undefined)
                    return;
                root._outputsRequested = false;
                root.outputs = Outputs.normalizeNiriOutputs(reply.Ok.Outputs);
                root.outputsState = "ok";
            }
        }
    }
}

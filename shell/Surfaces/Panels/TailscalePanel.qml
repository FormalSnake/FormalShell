import QtQuick
import Quickshell.Io
import qs.Core
import qs.Components
import qs.Services
import "../../Tailscale/model.js" as Tailscale

// Tailscale panel (DESIGN.md §Panels, M16 Task 8): the popout behind
// TailscaleWidget's bar cell — GithubPanel's poll-in-panel pattern (the one
// `tailscale status --json` poll lives HERE, not in the widget, so `panel
// open tailscale` over IPC renders honestly even when bar.layout never
// names the widget; the widget flips pollEnabled true from its own
// Component.onCompleted, same opt-in idiom). Honest states: `tailscale`
// missing from PATH (exit 127) or an unparsable/empty response both render
// dim NO TAILSCALE (Tailscale/model.js's own `ok:false`, the same shape a
// daemon-unreachable run produces — its error text is plain, not JSON);
// BackendState "NeedsLogin" renders dim NEEDS LOGIN; pre-first-answer
// renders LOADING.
//
// STATUS is one action cell (CONNECTED/STOPPED, running state inverted like
// NetworkPanel's connected row) that toggles `tailscale up`/`down` on
// click or Enter — a permission failure (verified against the real 1.98.8
// binary's own "Access denied: %v" wrapper, strings-dumped from the pinned
// nix store closure, not guessed) renders NOT OPERATOR inline instead of
// pretending the toggle worked; SWITCHOVER.md documents `tailscale set
// --operator=$USER` as the host-side prerequisite for it to ever succeed
// from this unprivileged shell. Below it, a self hostname+IP row (click
// copies the IP via a plain `wl-copy` Process, ClipboardService's own
// copy-back idiom). MACHINES lists every peer (name, dim IP, an
// ONLINE/OFFLINE indicator that only breathes — PowerPanel's charging-pulse
// idiom — while our own `tailscale up` is in flight), click copies that
// peer's IP.
//
// Keyboard nav (M14 pattern, Panel.keyPressed): a single numeric cursor
// spans the STATUS row (index 0) then each MACHINES row in order, Up/Down
// moves it, Enter activates whatever it's on — toggling STATUS or copying
// the cursored peer's IP. The self-hostname row and the NEEDS LOGIN/NO
// TAILSCALE honest states stay mouse-only, same as GithubPanel's rows.
Panel {
    id: root

    panelTitle: "TAILSCALE"
    panelWidth: Theme.space.popupWidthDefault

    property bool pollEnabled: false

    // "unknown" (pre-first-answer) | "missing" | "error" | "needsLogin" | "ok"
    property string pollState: "unknown"
    // Tailscale.parseStatus() result, meaningful only while pollState === "ok".
    property var status: null

    readonly property int _interval: {
        var v = Config.get("tailscale.intervalMs", 60000);
        return (typeof v === "number" && v > 0) ? v : 60000;
    }

    function _poll() {
        if (statusProc.running)
            return;
        statusProc.running = true;
    }

    onPollEnabledChanged: if (root.pollEnabled) root._poll()
    onIsOpenChanged: {
        if (root.isOpen) {
            root._poll();
            root._cursor = 0;
        }
    }

    Timer {
        interval: root._interval
        running: root.pollEnabled
        repeat: true
        onTriggered: root._poll()
    }

    // Tailscale's own state usually flips with the underlying link — poll
    // right after a reconnect instead of showing the pre-drop answer for up
    // to a minute (ConnectivityService).
    Connections {
        target: ConnectivityService
        function onReconnected() {
            if (root.pollEnabled || root.isOpen)
                root._poll();
        }
    }

    Process {
        id: statusProc
        command: ["sh", "-c", "command -v tailscale >/dev/null 2>&1 || exit 127; exec tailscale status --json"]
        stdout: StdioCollector {
            id: statusCollector
        }
        onExited: exitCode => {
            if (exitCode === 127) {
                root.pollState = "missing";
                root.status = null;
                return;
            }
            var parsed = Tailscale.parseStatus(statusCollector.text);
            if (!parsed.ok) {
                root.pollState = "error";
                root.status = null;
                return;
            }
            root.status = parsed;
            root.pollState = parsed.needsLogin ? "needsLogin" : "ok";
        }
    }

    // One toggle in flight at a time: "" | "up" | "down".
    property string _actionKind: ""
    // "" | "NOT OPERATOR" | "FAILED" | "TIMED OUT" — cleared on the next
    // attempt, otherwise sticks until then (NetworkPanel/BluetoothPanel's
    // own failure text persists the same way).
    property string _actionError: ""

    function _toggle() {
        if (root._actionKind !== "" || root.pollState !== "ok" || !root.status)
            return;
        root._actionKind = root.status.running ? "down" : "up";
        root._actionError = "";
        actionProc.command = ["sh", "-c", "command -v tailscale >/dev/null 2>&1 || exit 127; exec tailscale " + root._actionKind];
        actionTimeout.restart();
        actionProc.running = true;
    }

    // Real 1.98.8 binary text (strings-dumped from the pinned nix store
    // closure): API access-denied conditions — including the exact "must be
    // root, or be an operator" case a non-operator `tailscale up`/`down`
    // hits — all wrap through one `Access denied: %v` format string.
    Process {
        id: actionProc
        stderr: StdioCollector {
            id: actionStderr
        }
        onExited: exitCode => {
            actionTimeout.stop();
            if (exitCode === 127) {
                root._actionError = "FAILED";
            } else if (exitCode !== 0) {
                root._actionError = /access denied/i.test(actionStderr.text) ? "NOT OPERATOR" : "FAILED";
            }
            root._actionKind = "";
            root._poll();
        }
    }

    // Safety net (NetworkPanel/BluetoothPanel's actionTimeout idiom): if
    // `tailscale up`/`down` never exits, stop waiting on it honestly rather
    // than showing CONNECTING…/DISCONNECTING… forever. The process itself
    // isn't killed — same choice those two panels make — so a late real
    // exit still lands (harmlessly re-polling) once it happens.
    Timer {
        id: actionTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            root._actionError = "TIMED OUT";
            root._actionKind = "";
        }
    }

    function _copyIp(ip) {
        if (!ip)
            return;
        copyProc.exec({ command: ["wl-copy", ip] });
    }

    Process {
        id: copyProc
    }

    // Merged keyboard-cursor space: index 0 is the STATUS toggle, 1..n are
    // MACHINES rows in their already-sorted (online-first, then
    // alphabetical) order.
    readonly property var _rows: {
        if (root.pollState !== "ok")
            return [];
        var list = [{ kind: "status" }];
        var peers = root.status ? root.status.peers : [];
        for (var i = 0; i < peers.length; i++)
            list.push({ kind: "peer", peer: peers[i] });
        return list;
    }

    property int _cursor: 0
    on_RowsChanged: root._cursor = Math.max(0, Math.min(root._cursor, root._rows.length - 1))

    function _activateCursor() {
        if (root._cursor === 0) {
            root._toggle();
            return;
        }
        var row = root._rows[root._cursor];
        if (row && row.kind === "peer")
            root._copyIp(row.peer.ip);
    }

    Connections {
        target: root

        function onKeyPressed(event) {
            if (!root.isOpen || root.pollState !== "ok")
                return;
            // First Up/Down only reveals the cursor on the status row
            // (M26 Task 8, upstream's CursorSurface contract) — it does not
            // also move it, so the highlight appears where the user can see
            // it before anything happens.
            if (!root.cursorActive && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                root.cursorActive = true;
                event.accepted = true;
                return;
            }
            switch (event.key) {
            case Qt.Key_Up:
                root._cursor = Math.max(0, root._cursor - 1);
                event.accepted = true;
                break;
            case Qt.Key_Down:
                root._cursor = Math.min(root._rows.length - 1, root._cursor + 1);
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root._activateCursor();
                event.accepted = true;
                break;
            }
        }
    }

    Cell {
        visible: root.pollState === "unknown"
        width: parent.width

        MetaLabel { text: "LOADING" }
    }

    Cell {
        visible: root.pollState === "missing" || root.pollState === "error"
        width: parent.width

        MetaLabel { text: "NO TAILSCALE" }
    }

    Cell {
        visible: root.pollState === "needsLogin"
        width: parent.width

        MetaLabel { text: "NEEDS LOGIN" }
    }

    // The panel's own subject (M28 Task 5): this machine's own tailnet name,
    // the backend's connection state, connect/disconnect promoted into the
    // trailing slot — replaces the old STATUS row outright, which said the
    // same two things (running state, and the toggle itself).
    PanelHero {
        id: statusHero
        visible: root.pollState === "ok"
        width: parent.width
        glyph: "󰌘"
        title: (root.status && root.status.selfName) ? root.status.selfName : "UNKNOWN"
        meta: root._actionKind === "up" ? "CONNECTING…" : root._actionKind === "down" ? "DISCONNECTING…" : (root.status && root.status.running ? "CONNECTED" : "STOPPED")
        trailing: statusToggle
        hovered: root.cursorActive && root._cursor === 0
        interactive: true
        acceptedButtons: Qt.NoButton
        onContainsPointerChanged: if (statusHero.containsPointer) {
            root.cursorActive = true;
            root._cursor = 0;
        }
    }

    Component {
        id: statusToggle

        // Bare-label ink promotion (DESIGN.md §1.1's 2026-08-09 amendment):
        // no cell chrome, armed state promotes straight to accent instead
        // of a fill/inversion.
        MetaLabel {
            text: (root.status && root.status.running) ? "DISCONNECT" : "CONNECT"
            color: root._actionKind !== ""
                ? Theme.color.accent
                : (statusToggleHover.containsMouse ? Theme.color.foreground : Theme.color.foregroundDim)

            MouseArea {
                id: statusToggleHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root._toggle()
            }
        }
    }

    Cell {
        visible: root.pollState === "ok" && root._actionError !== ""
        width: parent.width

        MetaLabel { text: root._actionError; color: Theme.color.urgent }
    }

    // The hero above already names this machine; the IP is the one fact it
    // doesn't carry, so this row narrows to just that.
    Cell {
        id: selfCell
        visible: root.pollState === "ok" && root.status && Tailscale.selfIp(root.status) !== null
        width: parent.width

        Row {
            width: parent.width
            spacing: Theme.space.sm

            MetaLabel { text: "IP" }

            Text {
                text: root.status ? (Tailscale.selfIp(root.status) || "") : ""
                color: selfCell.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }
        }

        interactive: true
        onClicked: root._copyIp(root.status ? Tailscale.selfIp(root.status) : null)
    }

    Cell {
        visible: root.pollState === "ok"
        width: parent.width

        MetaLabel { text: "MACHINES / " + (root.status ? root.status.peers.length : 0) }
    }

    Component {
        id: peerRow

        Cell {
            id: peerCell
            required property var modelData
            required property int index
            width: parent.width
            hovered: root.cursorActive && root._cursor === (index + 1)
            onContainsPointerChanged: if (peerCell.containsPointer) {
                root.cursorActive = true;
                root._cursor = index + 1;
            }

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                Row {
                    width: parent.width
                    spacing: Theme.space.sm

                    Text {
                        width: parent.width - onlineText.width - parent.spacing
                        text: peerCell.modelData.name
                        color: peerCell.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.body
                        elide: Text.ElideRight
                    }

                    Text {
                        id: onlineText
                        text: peerCell.modelData.online ? "ONLINE" : "OFFLINE"
                        color: peerCell.modelData.online ? peerCell.dimForeground : Theme.color.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.caption
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: Theme.letterSpacing.meta

                        // Gated on root.isOpen too (M16 Task 12 hidden-
                        // surface audit): panel content stays instantiated
                        // behind a hidden window after close(), so an
                        // in-flight `tailscale up` closed mid-connect would
                        // otherwise keep this pulsing off-screen until the
                        // process exits.
                        SequentialAnimation on opacity {
                            running: root._actionKind === "up" && root.isOpen
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                            NumberAnimation { to: 1.0; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                        }
                    }
                }

                Text {
                    visible: peerCell.modelData.ip !== null
                    text: peerCell.modelData.ip || ""
                    color: Theme.color.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.caption
                }
            }

            interactive: peerCell.modelData.ip !== null
            onClicked: root._copyIp(peerCell.modelData.ip)
        }
    }

    Repeater {
        model: root.pollState === "ok" ? root.status.peers : []
        delegate: peerRow
    }

    Cell {
        visible: root.pollState === "ok" && root.status && root.status.peers.length === 0
        width: parent.width

        MetaLabel { text: "NONE" }
    }
}

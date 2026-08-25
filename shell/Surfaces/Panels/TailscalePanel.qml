import QtQuick
import Quickshell.Io
import qs.Core
import qs.Components
import qs.Services
import "../../Tailscale/model.js" as Tailscale

// Tailscale panel (DESIGN.md §3 "Panel", spec "Panels"): the popout behind
// TailscaleWidget's bar cell, on GithubPanel's poll-in-panel pattern (the
// one `tailscale status --json` poll lives HERE, not in the widget, so
// `panel open tailscale` over IPC renders honestly even when bar.layout
// never names the widget; the widget flips pollEnabled true from its own
// Component.onCompleted, same opt-in idiom). Honest states: `tailscale`
// missing from PATH (exit 127) or an unparsable/empty response both render
// dim NO TAILSCALE (Tailscale/model.js's own `ok:false`, the same shape a
// daemon-unreachable run produces, since its error text is plain rather than
// JSON); BackendState "NeedsLogin" renders dim NEEDS LOGIN; pre-first-answer
// renders LOADING.
//
// The hero names this machine and carries the backend's connection state,
// the header's `power` button runs `tailscale up`/`down`, and a permission
// failure (verified against the real 1.98.8 binary's own "Access denied: %v"
// wrapper, strings-dumped from the pinned nix store closure, not guessed)
// renders NOT OPERATOR inline instead of pretending the toggle worked;
// SWITCHOVER.md documents `tailscale set --operator=$USER` as the host-side
// prerequisite for it to ever succeed from this unprivileged shell. Below
// it, this machine's own IP row (activating it copies the address via a
// plain `wl-copy` Process, ClipboardService's own copy-back idiom), then
// `PEERS (n)`: a reachability dot, the hostname in mono, the platform and
// address as a caption. The dot is what breathes while our own `tailscale
// up` is in flight (PowerPanel's charging-pulse idiom).
//
// Keyboard (spec "Keyboard model"): one numeric cursor spans the hero
// (index 0), the IP row when there is one, then each peer. Enter toggles the
// connection on the hero and copies the address on any other row. The
// NEEDS LOGIN and NO TAILSCALE honest states carry no cursor.
Panel {
    id: root

    panelIcon: "network"
    panelTitle: "Tailscale"
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
        if (!root.isOpen)
            return;
        root._poll();
        root.cursorIndex = 0;
    }

    Timer {
        interval: root._interval
        running: root.pollEnabled
        repeat: true
        onTriggered: root._poll()
    }

    // Tailscale's own state usually flips with the underlying link, poll
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
    // "" | "NOT OPERATOR" | "FAILED" | "TIMED OUT", cleared on the next
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
    // closure): API access-denied conditions, including the exact "must be
    // root, or be an operator" case a non-operator `tailscale up`/`down`
    // hits, all wrap through one `Access denied: %v` format string.
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
    // than showing Connecting/Disconnecting forever. The process itself
    // isn't killed, same choice those two panels make, so a late real
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

    readonly property string _selfIp: (root.pollState === "ok" && root.status)
        ? (Tailscale.selfIp(root.status) || "")
        : ""

    readonly property var _peers: (root.pollState === "ok" && root.status) ? root.status.peers : []

    // One numeric cursor space over everything that answers Enter: index 0
    // is the hero (the connection toggle), then this machine's own IP row
    // when it has one, then each peer in its already-sorted (online-first,
    // then alphabetical) order.
    readonly property int _peerOffset: 1 + (root._selfIp !== "" ? 1 : 0)

    readonly property var _rows: {
        if (root.pollState !== "ok")
            return [];
        var list = [{ kind: "status" }];
        if (root._selfIp !== "")
            list.push({ kind: "self" });
        for (var i = 0; i < root._peers.length; i++)
            list.push({ kind: "peer", peer: root._peers[i] });
        return list;
    }

    cursorCount: root._rows.length

    onCursorActivated: index => {
        var row = (index >= 0 && index < root._rows.length) ? root._rows[index] : null;
        if (!row)
            return;
        if (row.kind === "status")
            root._toggle();
        else if (row.kind === "self")
            root._copyIp(root._selfIp);
        else
            root._copyIp(row.peer.ip);
    }

    function _pointAt(index) {
        root.cursorActive = true;
        root.cursorIndex = index;
    }

    titleActions: [
        IconButton {
            name: "power"
            enabled: root.pollState === "ok" && root._actionKind === ""
            onClicked: root._toggle()
        },
        IconButton {
            name: "refresh-cw"
            onClicked: root._poll()
        }
    ]

    Cell {
        visible: root.pollState === "unknown"
        width: parent.width

        SectionLabel { text: "LOADING" }
    }

    Cell {
        visible: root.pollState === "missing" || root.pollState === "error"
        width: parent.width

        SectionLabel { text: "NO TAILSCALE" }
    }

    Cell {
        visible: root.pollState === "needsLogin"
        width: parent.width

        SectionLabel { text: "NEEDS LOGIN" }
    }

    // The panel's own subject: this machine's tailnet name and the backend's
    // connection state. The header's power button flips it, and so does Enter
    // with the cursor here.
    PanelHero {
        id: statusHero
        visible: root.pollState === "ok"
        width: parent.width
        title: (root.status && root.status.selfName) ? root.status.selfName : "Unknown"
        meta: root._actionKind === "up"
            ? "Connecting"
            : root._actionKind === "down"
                ? "Disconnecting"
                : (root.status && root.status.running ? "Connected" : "Stopped")
        cursor: root.cursorActive && root.cursorIndex === 0
        interactive: true
        acceptedButtons: Qt.NoButton
        onContainsPointerChanged: if (statusHero.containsPointer) root._pointAt(0)

        leading: Component {
            Icon {
                name: "network"
                size: Theme.fontSize.heading
                color: statusHero.foreground
            }
        }
    }

    Cell {
        visible: root.pollState === "ok" && root._actionError !== ""
        width: parent.width
        destructive: true

        SectionLabel { text: root._actionError; color: Theme.color.destructive }
    }

    // The hero above already names this machine; the IP is the one fact it
    // doesn't carry, so this row narrows to just that.
    Cell {
        id: selfCell
        visible: root._selfIp !== ""
        width: parent.width
        cursor: root.cursorActive && root.cursorIndex === 1

        interactive: true
        onContainsPointerChanged: if (selfCell.containsPointer) root._pointAt(1)
        onClicked: root._copyIp(root._selfIp)

        Item {
            width: parent.width
            height: Math.max(selfLabel.implicitHeight, selfValue.implicitHeight)

            SectionLabel {
                id: selfLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "IP"
            }

            // An address is an identifier, so it takes the mono face (spec
            // "Type").
            Text {
                id: selfValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root._selfIp
                color: selfCell.foreground
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSize.body
                font.weight: Theme.weight.medium
            }
        }
    }

    Component {
        id: peerRow

        Cell {
            id: peerCell
            required property var modelData
            required property int index
            width: parent.width

            readonly property int _cursorIndex: peerCell.index + root._peerOffset

            cursor: root.cursorActive && root.cursorIndex === peerCell._cursorIndex

            interactive: peerCell.modelData.ip !== null
            onContainsPointerChanged: if (peerCell.containsPointer) root._pointAt(peerCell._cursorIndex)
            onClicked: root._copyIp(peerCell.modelData.ip)

            Item {
                width: parent.width
                height: peerColumn.implicitHeight

                // The reachability mark (DESIGN.md §3's own dot idiom):
                // `primary` for a peer that is up, muted for one that is not.
                Rectangle {
                    id: onlineDot
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.space.md
                    height: width
                    radius: width / 2
                    color: peerCell.modelData.online ? Theme.color.primary : Theme.color.mutedForeground

                    // Gated on root.isOpen too (M16 Task 12 hidden-surface
                    // audit): panel content stays instantiated behind a
                    // hidden window after close(), so an in-flight
                    // `tailscale up` closed mid-connect would otherwise keep
                    // this pulsing off-screen until the process exits.
                    SequentialAnimation on opacity {
                        running: root._actionKind === "up" && root.isOpen
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                        NumberAnimation { to: 1.0; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                    }
                }

                Column {
                    id: peerColumn
                    anchors.left: onlineDot.right
                    anchors.leftMargin: Theme.space.iconGap
                    anchors.right: parent.right
                    spacing: Theme.space.xxs

                    // A hostname is an identifier, so it takes the mono face
                    // (spec "Type").
                    Text {
                        width: parent.width
                        text: peerCell.modelData.name
                        color: peerCell.foreground
                        font.family: Theme.fontFamilyMono
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                        elide: Text.ElideRight
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.space.iconGap

                        // The platform name is a word and the address a
                        // value, so the caption sets each by that rule
                        // rather than switching family inside one string.
                        Text {
                            visible: peerCell.modelData.os !== null
                            text: peerCell.modelData.os || ""
                            color: peerCell.dimForeground
                            font.family: Theme.fontFamilySans
                            font.pixelSize: Theme.fontSize.caption
                        }

                        Text {
                            visible: peerCell.modelData.ip !== null
                            text: peerCell.modelData.ip || ""
                            color: peerCell.dimForeground
                            font.family: Theme.fontFamilyMono
                            font.pixelSize: Theme.fontSize.caption
                        }
                    }
                }
            }
        }
    }

    Column {
        width: parent.width
        visible: root.pollState === "ok"
        spacing: Theme.space.rowGap

        SectionLabel { text: "PEERS"; count: root._peers.length }

        Cell {
            visible: root._peers.length === 0
            width: parent.width

            SectionLabel { text: "NONE" }
        }

        Repeater {
            model: root._peers
            delegate: peerRow
        }
    }
}

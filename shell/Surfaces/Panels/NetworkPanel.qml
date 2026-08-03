import QtQuick
import Quickshell.Io
import Quickshell.Networking
import qs.Core
import qs.Components
import "../../Network/model.js" as NetworkModel
import "../../Network/speedtest.js" as SpeedTest

// Network panel (DESIGN.md §Panels, spec §2, M6 Task 6; wifi behavior parity
// M14 Task 2): a ledger table of connections grouped WIRED then WI-FI
// (mirroring AudioPanel's OUTPUT/INPUT split), each row a full-width cell,
// the active connection inverted. WIRED stays the simple always-visible
// connect/disconnect row it always was. WI-FI is the omarchy-parity surface:
// a WI-FI POWER toggle (BluetoothPanel's adapter-POWER idiom), rows sorted
// by Network/model.js (connected → known → signal desc) under KNOWN/
// AVAILABLE headers, a mono signal bar, a lock glyph for secured networks, a
// status subline (CONNECTING…/failure text), an inline masked passphrase
// prompt for secured-unknown networks (an IDENTITY field too for 802.1x
// EAP), and a hover-revealed FORGET action on known rows. The wifi device's
// `scannerEnabled` tracks the panel's own `isOpen` (live list while looking,
// idle radio once closed), omarchy's exact idiom. Bound directly to
// Quickshell.Networking, same as AudioPanel binds Pipewire directly rather
// than going through a Services wrapper. Honest empty state: "NO DEVICES"
// when Networking.devices is empty; a section with zero rows simply omits
// its header rather than inventing a placeholder row.
//
// SPEED TEST (M16 Task 9, "flat ledger rows, no gauges": omarchy's own
// SpeedTestPanel.qml renders a pair of floating arc gauges; that chrome is
// deliberately left behind, only the measurement technique is ported, and
// reimplemented rather than copied). A RUN cell kicks off `_startSpeedTest`:
// resolve the active interface via a real `ip route get 1.1.1.1` Process
// (`SpeedTest.parseIface`), confirm `curl` is on PATH, then run DOWNLOAD
// then UPLOAD in turn. Each phase spawns `_stWorkerCount` parallel `curl`
// Processes: download loops plain GETs against Cloudflare's `__down`
// endpoint, upload loops a single indefinitely-streaming
// `-X POST -T /dev/zero` against `__up` (verified directly: curl treats
// `/dev/zero` as a file with no EOF and streams it chunked until killed),
// while a 500ms sampling Timer reads `/sys/class/net/<iface>/statistics/
// {rx,tx}_bytes` via `cat` (no shell) and folds each reading through
// `SpeedTest.addSample`. The phase's own bounded-duration Timer, not
// transfer completion, ends it: `_stopWorkers` sets each worker's `running`
// to false, which sends SIGTERM (Quickshell's own documented behavior) to
// that worker's `bash -c` wrapper; the wrapper's `trap '... EXIT'` calls
// `pkill -TERM -P $$` on itself first, killing its own foreground curl by
// PID before it exits. Verified directly: a bare SIGTERM to the wrapper
// alone orphans a still-running foreground child, and the trap's explicit
// pkill closes that gap, so "kill the curls by PID on stop" is real, not
// just SIGTERM-and-hope. Closing the panel mid-run does the same ("...on
// close"). Honest states: no resolvable interface (including `ip` missing)
// renders `NO NETWORK`, no `curl` on PATH renders `NO CURL`. Results stay
// on screen until the panel closes.
Panel {
    id: root

    panelTitle: "NETWORK"

    // EAP profile creation shells out to nmcli (Constraints: the password
    // never touches argv: it arrives over the Process's own stdin, read by
    // `IFS= read -r pw` and fed straight into nmcli's scriptable `connection
    // edit` editor). Command shape mirrored from omarchy's
    // enterpriseConnectScript (~/Developer/omarchy/shell/plugins/panels/
    // network/Model.js:322-333) with one addition: the leading `command -v`
    // guard omarchy doesn't need (it assumes nmcli is always present) but
    // this shell's "NO NMCLI" honest-unavailable-state contract does: the
    // script's own `false`-swallowing failure path (`|| { delete; false; }`)
    // would otherwise mask a missing binary as a generic connect failure.
    readonly property string _enterpriseScript:
        "command -v nmcli >/dev/null 2>&1 || exit 127;" +
        "u=$(uuidgen); IFS= read -r pw;" +
        " nmcli connection add type wifi con-name \"$1\" ssid \"$1\" connection.uuid \"$u\"" +
        " wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2" +
        " 802-1x.identity \"$2\" 802-1x.auth-timeout 8 >/dev/null" +
        " && printf 'set 802-1x.password %s\\nsave\\nquit\\n' \"$pw\" | nmcli connection edit uuid \"$u\" >/dev/null" +
        " && nmcli connection up uuid \"$u\"" +
        " || { nmcli connection delete uuid \"$u\" >/dev/null 2>&1; false; }"

    readonly property var _entries: {
        var out = [];
        var devices = Networking.devices.values;
        for (var i = 0; i < devices.length; i++) {
            var device = devices[i];
            var networks = device.networks.values;
            for (var j = 0; j < networks.length; j++)
                out.push({ device: device, network: networks[j] });
        }
        return out;
    }
    readonly property var _wiredEntries: root._entries.filter(function (e) { return e.device.type === DeviceType.Wired; })
    readonly property var _wifiEntries: root._entries.filter(function (e) { return e.device.type === DeviceType.Wifi; })

    readonly property var _wifiSorted: NetworkModel.sortWifiRows(root._wifiEntries.map(function (e) {
        return {
            device: e.device,
            network: e.network,
            connected: e.network.connected,
            known: e.network.known,
            signalStrength: e.network.signalStrength,
            security: e.network.security
        };
    }))
    readonly property var _knownRows: root._wifiSorted.filter(function (r) { return NetworkModel.sectionOf(r) === "KNOWN"; })
    readonly property var _availableRows: root._wifiSorted.filter(function (r) { return NetworkModel.sectionOf(r) === "AVAILABLE"; })

    readonly property var _wifiDevices: Networking.devices.values.filter(function (d) { return d.type === DeviceType.Wifi; })
    readonly property bool _hasWifiDevice: root._wifiDevices.length > 0

    function _applyScanner() {
        for (var i = 0; i < root._wifiDevices.length; i++)
            root._wifiDevices[i].scannerEnabled = root.isOpen;
    }

    on_WifiDevicesChanged: root._applyScanner()
    Component.onCompleted: root._applyScanner()

    onIsOpenChanged: {
        root._applyScanner();
        if (!root.isOpen) {
            root._cancelPasswordPrompt();
            root._cursorSsid = "";
            root._stopSpeedTest();
        }
    }

    // ---- Speed test (M16 Task 9) ----------------------------------------

    readonly property int _stWorkerCount: 4
    readonly property int _stPhaseDurationMs: 5000
    readonly property int _stSampleIntervalMs: 500
    readonly property string _stDownloadUrl: "https://speed.cloudflare.com/__down?bytes=25000000"
    readonly property string _stUploadUrl: "https://speed.cloudflare.com/__up"

    // Each worker loops its own foreground curl until killed; the trap
    // fires on the SIGTERM `running = false` sends (Process.running's own
    // documented behavior), `pkill -TERM -P $$` reaching the in-flight curl
    // before the wrapper itself exits (see the header comment for why a
    // bare SIGTERM to the wrapper alone isn't enough).
    readonly property string _stDownloadScript:
        "trap 'pkill -TERM -P $$ 2>/dev/null' EXIT;" +
        " url=\"$1\";" +
        " while true; do curl -s -o /dev/null \"$url\" || break; done"
    readonly property string _stUploadScript:
        "trap 'pkill -TERM -P $$ 2>/dev/null' EXIT;" +
        " url=\"$1\";" +
        " while true; do curl -s -o /dev/null -X POST -T /dev/zero \"$url\" || break; done"

    // "idle" | "resolving" | "down" | "up" | "done"
    property string _stPhase: "idle"
    property string _stError: ""
    property string _stIface: ""
    property var _stDownWindow: SpeedTest.initWindow()
    property var _stUpWindow: SpeedTest.initWindow()
    property real _stDownResult: 0
    property real _stUpResult: 0

    readonly property bool _stRunning: root._stPhase === "resolving" || root._stPhase === "down" || root._stPhase === "up"

    readonly property var _stWorkers: [speedWorker0, speedWorker1, speedWorker2, speedWorker3]

    function _startSpeedTest() {
        if (root._stRunning)
            return;
        root._stError = "";
        root._stIface = "";
        root._stDownWindow = SpeedTest.initWindow();
        root._stUpWindow = SpeedTest.initWindow();
        root._stDownResult = 0;
        root._stUpResult = 0;
        root._stPhase = "resolving";
        ifaceProc.running = true;
    }

    function _stopSpeedTest() {
        if (root._stPhase === "idle")
            return;
        if (ifaceProc.running)
            ifaceProc.running = false;
        if (curlCheckProc.running)
            curlCheckProc.running = false;
        root._stopWorkers();
        statTimer.stop();
        phaseTimer.stop();
        root._stPhase = "idle";
        root._stError = "";
        root._stDownResult = 0;
        root._stUpResult = 0;
    }

    function _abortSpeedTest(message) {
        root._stopWorkers();
        statTimer.stop();
        phaseTimer.stop();
        root._stError = message;
        root._stPhase = "done";
    }

    function _startWorkers(direction) {
        var script = direction === "down" ? root._stDownloadScript : root._stUploadScript;
        var url = direction === "down" ? root._stDownloadUrl : root._stUploadUrl;
        for (var i = 0; i < root._stWorkers.length; i++) {
            var worker = root._stWorkers[i];
            worker.command = ["bash", "-c", script, "speedtest-" + direction, url];
            worker.running = true;
        }
    }

    function _stopWorkers() {
        for (var i = 0; i < root._stWorkers.length; i++) {
            if (root._stWorkers[i].running)
                root._stWorkers[i].running = false;
        }
    }

    function _beginPhase(direction) {
        root._stPhase = direction;
        if (direction === "down")
            root._stDownWindow = SpeedTest.initWindow();
        else
            root._stUpWindow = SpeedTest.initWindow();
        root._startWorkers(direction);
        root._sample();
        phaseTimer.restart();
    }

    function _endPhase() {
        root._stopWorkers();
        if (root._stPhase === "down") {
            root._stDownResult = root._stDownWindow.avgMbps;
            root._beginPhase("up");
        } else if (root._stPhase === "up") {
            root._stUpResult = root._stUpWindow.avgMbps;
            statTimer.stop();
            root._stPhase = "done";
        }
    }

    function _sample() {
        if (root._stIface === "" || statProc.running)
            return;
        statProc.command = ["cat", "/sys/class/net/" + root._stIface + "/statistics/rx_bytes", "/sys/class/net/" + root._stIface + "/statistics/tx_bytes"];
        statProc.running = true;
    }

    // ip route get 1.1.1.1 -> the active interface's name (SpeedTest.parseIface).
    // No route at all, or `ip` missing from PATH, both leave stdout without
    // a "dev <iface>" pair, the same honest NO NETWORK either way.
    Process {
        id: ifaceProc
        command: ["sh", "-c", "ip route get 1.1.1.1 2>/dev/null"]
        stdout: StdioCollector {
            id: ifaceCollector
        }
        onExited: exitCode => {
            // Guards against the panel closing (or the run being stopped)
            // between this Process starting and exiting: _stopSpeedTest()
            // resets _stPhase to "idle", and without this check the chain
            // below would resurrect a full run against a closed panel.
            if (root._stPhase !== "resolving")
                return;
            var iface = SpeedTest.parseIface(ifaceCollector.text);
            if (!iface) {
                root._abortSpeedTest("NO NETWORK");
                return;
            }
            root._stIface = iface;
            curlCheckProc.running = true;
        }
    }

    Process {
        id: curlCheckProc
        command: ["sh", "-c", "command -v curl >/dev/null 2>&1"]
        onExited: exitCode => {
            // Same resurrection guard as ifaceProc.onExited above.
            if (root._stPhase !== "resolving")
                return;
            if (exitCode !== 0) {
                root._abortSpeedTest("NO CURL");
                return;
            }
            root._beginPhase("down");
        }
    }

    // Sampling read: two argv paths straight to `cat`, no shell. An
    // interface that disappears mid-run (or never had readable statistics)
    // makes SpeedTest.parseStatBytes() return null, which aborts the whole
    // test honestly rather than reporting a stale/invented rate.
    Process {
        id: statProc
        stdout: StdioCollector {
            id: statCollector
        }
        onExited: exitCode => {
            var stats = SpeedTest.parseStatBytes(statCollector.text);
            if (!stats) {
                root._abortSpeedTest("NO NETWORK");
                return;
            }
            var t = Date.now();
            if (root._stPhase === "down")
                root._stDownWindow = SpeedTest.addSample(root._stDownWindow, t, stats.rx);
            else if (root._stPhase === "up")
                root._stUpWindow = SpeedTest.addSample(root._stUpWindow, t, stats.tx);
        }
    }

    Timer {
        id: statTimer
        interval: root._stSampleIntervalMs
        repeat: true
        running: root._stPhase === "down" || root._stPhase === "up"
        onTriggered: root._sample()
    }

    // The phase's own bounded duration ends it, not transfer completion and
    // not the sampling cadence.
    Timer {
        id: phaseTimer
        interval: root._stPhaseDurationMs
        repeat: false
        onTriggered: root._endPhase()
    }

    Process { id: speedWorker0 }
    Process { id: speedWorker1 }
    Process { id: speedWorker2 }
    Process { id: speedWorker3 }

    // One action in flight at a time (omarchy's runNetworkAction/actionKind
    // pattern): "connect" | "disconnect" | "forget" | "" while idle.
    property string _actionSsid: ""
    property string _actionKind: ""
    property string _failureSsid: ""
    property string _failureText: ""

    // One inline passphrase/identity prompt open at a time.
    property string _passwordSsid: ""
    property string _passwordText: ""
    property string _identityText: ""

    // Keyboard cursor over the combined KNOWN+AVAILABLE row order, tracked
    // by ssid rather than a numeric index since the two sections render as
    // separate Repeaters (PowerPanel's numeric _cursor doesn't fit a table
    // that splits across two headers).
    property string _cursorSsid: ""

    function _wifiIndexForSsid(ssid) {
        for (var i = 0; i < root._wifiSorted.length; i++) {
            if ((root._wifiSorted[i].network.name || "") === ssid)
                return i;
        }
        return -1;
    }

    function _moveCursor(delta) {
        if (root._wifiSorted.length === 0) {
            root._cursorSsid = "";
            return;
        }
        var idx = root._wifiIndexForSsid(root._cursorSsid);
        if (idx < 0)
            idx = delta > 0 ? 0 : root._wifiSorted.length - 1;
        else
            idx = Math.max(0, Math.min(root._wifiSorted.length - 1, idx + delta));
        root._cursorSsid = root._wifiSorted[idx].network.name || "";
    }

    // Panel.qml's shared keyboard-nav hook (M6 Task 7, PowerPanel's consumer
    // pattern): Up/Down move the cursor, Enter activates it. Bails out
    // entirely while a passphrase prompt is open: that field owns real Qt
    // keyboard focus then, so typing (and its own Enter/Escape) goes to the
    // prompt, never the cursor.
    Connections {
        target: root

        function onKeyPressed(event) {
            if (!root.isOpen || root._passwordSsid !== "")
                return;
            switch (event.key) {
            case Qt.Key_Up:
                root._moveCursor(-1);
                event.accepted = true;
                break;
            case Qt.Key_Down:
                root._moveCursor(1);
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                var idx = root._wifiIndexForSsid(root._cursorSsid);
                if (idx >= 0)
                    root._activateWifiRow(root._wifiSorted[idx].network);
                event.accepted = true;
                break;
            }
        }
    }

    function _runAction(kind, network) {
        if (root._actionKind !== "" || !network)
            return false;
        root._actionSsid = network.name || "";
        root._actionKind = kind;
        root._failureSsid = "";
        root._failureText = "";
        actionTimeout.restart();
        return true;
    }

    function _clearAction() {
        actionTimeout.stop();
        if (root._actionKind === "connect")
            root._passwordSsid = "";
        root._actionSsid = "";
        root._actionKind = "";
        root._failureSsid = "";
        root._failureText = "";
    }

    function _checkActionCompletion(network) {
        if (!network || root._actionKind === "" || root._actionSsid !== (network.name || ""))
            return;
        if (root._actionKind === "connect" && network.connected) root._clearAction();
        else if (root._actionKind === "disconnect" && !network.connected && !network.stateChanging) root._clearAction();
        else if (root._actionKind === "forget" && !network.known && !network.stateChanging) root._clearAction();
    }

    function _failAction(network, reason) {
        if (!network || root._actionKind === "" || root._actionSsid !== (network.name || ""))
            return;
        actionTimeout.stop();
        root._failureSsid = root._actionSsid;
        root._failureText = NetworkModel.failureText(reason);
        root._actionSsid = "";
        root._actionKind = "";
        if (reason === NetworkModel.ConnectionFailReason.NoSecrets)
            root._openPasswordPrompt(network.name || "");
    }

    function _openPasswordPrompt(ssid) {
        if (root._passwordSsid !== ssid) {
            root._passwordText = "";
            root._identityText = "";
        }
        root._passwordSsid = ssid;
    }

    function _cancelPasswordPrompt() {
        root._passwordSsid = "";
        root._passwordText = "";
        root._identityText = "";
    }

    // Row activation (click or Enter-on-cursor): connected → disconnect;
    // secured and not yet known → open the inline prompt; otherwise a plain
    // connect (open network, or a known network reusing its saved secrets).
    function _activateWifiRow(network) {
        if (!network || root._actionKind !== "")
            return;
        if (network.connected) {
            if (root._runAction("disconnect", network))
                network.disconnect();
            return;
        }
        var ssid = network.name || "";
        if (root._passwordSsid === ssid)
            return;
        if (NetworkModel.isSecured(network.security) && !network.known) {
            root._openPasswordPrompt(ssid);
            return;
        }
        if (root._runAction("connect", network))
            network.connect();
    }

    function _forgetNetwork(network) {
        if (!network)
            return;
        if (root._runAction("forget", network))
            network.forget();
    }

    function _submitPassword(network) {
        if (!network || root._actionKind !== "" || root._passwordText.length === 0)
            return;
        if (NetworkModel.isEnterprise(network.security)) {
            if (root._identityText.length === 0)
                return;
            root._connectEnterprise(network, root._identityText, root._passwordText);
            return;
        }
        var psk = root._passwordText;
        if (root._runAction("connect", network))
            network.connectWithPsk(psk);
    }

    function _connectEnterprise(network, identity, password) {
        if (!root._runAction("connect", network))
            return;
        enterpriseProc.targetSsid = network.name || "";
        enterpriseProc.secret = password;
        enterpriseProc.command = ["bash", "-c", root._enterpriseScript, "nmcli-eap", network.name || "", identity];
        enterpriseProc.running = true;
    }

    // Safety net (omarchy's actionTimeout, Panel.qml:1025-1041 there): if
    // the completion signals above never fire, this clears a stuck busy row
    // to an honest "TIMED OUT" instead of "Connecting…" forever.
    Timer {
        id: actionTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            if (root._actionKind === "")
                return;
            root._failureSsid = root._actionSsid;
            root._failureText = "TIMED OUT";
            root._actionSsid = "";
            root._actionKind = "";
        }
    }

    // 802.1x profile creation/activation (see _enterpriseScript above). The
    // secret is written to stdin the instant the process starts and dropped
    // from JS memory immediately after: never argv, never logged, never
    // lingering.
    Process {
        id: enterpriseProc
        property string secret: ""
        property string targetSsid: ""
        stdinEnabled: true

        onStarted: {
            enterpriseProc.write(enterpriseProc.secret + "\n");
            enterpriseProc.secret = "";
        }

        onExited: function (exitCode) {
            if (root._actionKind !== "connect" || root._actionSsid !== enterpriseProc.targetSsid)
                return;
            actionTimeout.stop();
            if (exitCode === 0) {
                root._clearAction();
                return;
            }
            root._actionSsid = "";
            root._actionKind = "";
            root._failureSsid = enterpriseProc.targetSsid;
            root._failureText = exitCode === 127 ? "NO NMCLI" : NetworkModel.failureText(NetworkModel.ConnectionFailReason.Unknown);
        }
    }

    Component {
        id: networkRow

        Cell {
            id: netCell
            required property var modelData
            width: parent.width
            selected: netCell.modelData.network.connected

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                Row {
                    width: parent.width
                    spacing: Theme.space.sm

                    Text {
                        width: parent.width - actionCell.width - parent.spacing
                        text: netCell.modelData.network.name || "(unnamed)"
                        color: netCell.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.fontSize.body
                        elide: Text.ElideRight
                    }

                    Cell {
                        id: actionCell
                        width: implicitWidth
                        height: implicitHeight
                        selected: netCell.modelData.network.connected

                        MetaLabel {
                            text: netCell.modelData.network.connected ? "DISCONNECT" : "CONNECT"
                            color: actionCell.foreground
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (netCell.modelData.network.connected)
                                    netCell.modelData.network.disconnect();
                                else
                                    netCell.modelData.network.connect();
                            }
                        }
                    }
                }

                Text {
                    visible: typeof netCell.modelData.network.signalStrength === "number"
                    text: NetworkModel.signalBar(netCell.modelData.network.signalStrength) + "  " + Math.round(netCell.modelData.network.signalStrength * 100) + "%"
                    color: netCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.caption
                }
            }
        }
    }

    Component {
        id: wifiRow

        Cell {
            id: wifiCell
            required property var modelData
            width: parent.width
            selected: wifiCell.modelData.network.connected
            hovered: rowMouse.containsMouse || forgetMouse.containsMouse || (root._cursorSsid !== "" && root._cursorSsid === wifiCell._ssid)

            readonly property var _network: wifiCell.modelData.network
            readonly property string _ssid: wifiCell._network.name || ""
            readonly property bool _secured: NetworkModel.isSecured(wifiCell._network.security)
            readonly property bool _enterprise: NetworkModel.isEnterprise(wifiCell._network.security)
            readonly property bool _promptOpen: root._passwordSsid !== "" && root._passwordSsid === wifiCell._ssid
            readonly property bool _canForget: wifiCell._network.known && !wifiCell._network.connected
            readonly property string _statusText: {
                if (root._actionKind !== "" && root._actionSsid === wifiCell._ssid) {
                    if (root._actionKind === "connect") return "CONNECTING…";
                    if (root._actionKind === "disconnect") return "DISCONNECTING…";
                    return "FORGETTING…";
                }
                if (root._failureSsid !== "" && root._failureSsid === wifiCell._ssid)
                    return root._failureText;
                return "";
            }
            readonly property bool _isFailed: root._failureSsid !== "" && root._failureSsid === wifiCell._ssid && (root._actionKind === "" || root._actionSsid !== wifiCell._ssid)

            Connections {
                target: wifiCell._network

                function onConnectionFailed(reason) {
                    root._failAction(wifiCell._network, reason);
                }
                function onConnectedChanged() {
                    root._checkActionCompletion(wifiCell._network);
                }
                function onKnownChanged() {
                    root._checkActionCompletion(wifiCell._network);
                }
                function onStateChangingChanged() {
                    root._checkActionCompletion(wifiCell._network);
                }
            }

            Column {
                id: rowColumn
                width: parent.width
                spacing: Theme.space.xxs

                Item {
                    id: topLine
                    width: parent.width
                    height: Math.max(leftBits.implicitHeight, ssidText.implicitHeight, forgetCell.height)

                    Row {
                        id: leftBits
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space.sm

                        Text {
                            text: NetworkModel.signalBar(wifiCell._network.signalStrength)
                            color: wifiCell.foreground
                            font.family: Theme.font.family
                            font.pixelSize: Theme.fontSize.body
                        }

                        Text {
                            // md-lock U+F033E, verified against the pinned
                            // nerd-fonts-jetbrains-mono cmap (nix/testvm.nix)
                            // via fonttools ttx, not memory: same md- glyph
                            // family NetworkWidget.qml already uses.
                            visible: wifiCell._secured
                            text: "󰌾"
                            color: wifiCell.foreground
                            font.family: Theme.font.family
                            font.pixelSize: Theme.fontSize.body
                        }
                    }

                    Cell {
                        id: forgetCell
                        visible: wifiCell._canForget
                        opacity: wifiCell._canForget && wifiCell.hovered ? 1 : 0
                        enabled: opacity > 0 && root._actionKind === ""
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: implicitWidth
                        height: implicitHeight

                        Behavior on opacity {
                            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
                        }

                        MetaLabel {
                            text: "FORGET"
                            color: Theme.color.urgent
                        }

                        MouseArea {
                            id: forgetMouse
                            anchors.fill: parent
                            enabled: forgetCell.enabled
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._forgetNetwork(wifiCell._network)
                        }
                    }

                    Text {
                        id: ssidText
                        anchors.left: leftBits.right
                        anchors.leftMargin: Theme.space.sm
                        anchors.right: wifiCell._canForget ? forgetCell.left : parent.right
                        anchors.rightMargin: wifiCell._canForget ? Theme.space.sm : 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: wifiCell._ssid !== "" ? wifiCell._ssid : "HIDDEN"
                        color: wifiCell._ssid !== "" ? wifiCell.foreground : Theme.color.foregroundDim
                        elide: Text.ElideRight
                        font.family: Theme.font.family
                        font.pixelSize: Theme.fontSize.body
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: wifiCell._canForget ? forgetCell.left : parent.right
                        enabled: root._actionKind === ""
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._activateWifiRow(wifiCell._network)
                    }
                }

                Text {
                    visible: wifiCell._statusText !== ""
                    text: wifiCell._statusText
                    color: wifiCell._isFailed ? Theme.color.urgent : wifiCell.foreground
                    font.italic: wifiCell._isFailed
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.caption
                }

                Column {
                    width: parent.width
                    visible: wifiCell._promptOpen
                    spacing: Theme.space.xxs

                    Item {
                        width: parent.width
                        height: identityInput.implicitHeight
                        visible: wifiCell._enterprise

                        MetaLabel {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: identityInput.text.length === 0
                            text: "IDENTITY (USER@DOMAIN)"
                        }

                        TextInput {
                            id: identityInput
                            anchors.left: parent.left
                            anchors.right: parent.right
                            color: Theme.color.foreground
                            font.family: Theme.font.family
                            font.pixelSize: Theme.fontSize.body
                            selectByMouse: true
                            focus: wifiCell._promptOpen && wifiCell._enterprise
                            text: wifiCell._promptOpen ? root._identityText : ""

                            onTextChanged: if (wifiCell._promptOpen && text !== root._identityText) root._identityText = text;
                            onAccepted: passphraseInput.forceActiveFocus()
                            Keys.onEscapePressed: event => {
                                root._cancelPasswordPrompt();
                                event.accepted = true;
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: passphraseInput.implicitHeight

                        MetaLabel {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: passphraseInput.text.length === 0
                            text: "ENTER PASSPHRASE"
                        }

                        TextInput {
                            id: passphraseInput
                            anchors.left: parent.left
                            anchors.right: parent.right
                            color: Theme.color.foreground
                            font.family: Theme.font.family
                            font.pixelSize: Theme.fontSize.body
                            echoMode: TextInput.Password
                            passwordCharacter: "●"
                            selectByMouse: true
                            text: wifiCell._promptOpen ? root._passwordText : ""

                            onTextChanged: if (wifiCell._promptOpen && text !== root._passwordText) root._passwordText = text;
                            onAccepted: root._submitPassword(wifiCell._network)
                            Keys.onEscapePressed: event => {
                                root._cancelPasswordPrompt();
                                event.accepted = true;
                            }
                            onVisibleChanged: if (visible && !wifiCell._enterprise) Qt.callLater(passphraseInput.forceActiveFocus);
                            Component.onCompleted: if (visible && !wifiCell._enterprise) Qt.callLater(passphraseInput.forceActiveFocus);
                        }
                    }
                }
            }
        }
    }

    Cell {
        visible: root._wiredEntries.length === 0 && root._wifiEntries.length === 0
        width: parent.width

        MetaLabel { text: "NO DEVICES" }
    }

    Cell {
        visible: root._wiredEntries.length > 0
        width: parent.width

        MetaLabel { text: "WIRED" }
    }

    Repeater {
        model: root._wiredEntries
        delegate: networkRow
    }

    Cell {
        id: wifiPowerCell
        visible: root._hasWifiDevice
        width: parent.width

        Row {
            width: parent.width
            spacing: Theme.space.sm

            Text {
                width: parent.width - wifiPowerToggle.width - parent.spacing
                text: "WI-FI"
                color: wifiPowerCell.foreground
                font.family: Theme.font.family
                font.pixelSize: Theme.fontSize.body
            }

            Cell {
                id: wifiPowerToggle
                width: implicitWidth
                height: implicitHeight
                selected: Networking.wifiEnabled

                MetaLabel {
                    text: "WI-FI POWER"
                    color: wifiPowerToggle.foreground
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                }
            }
        }
    }

    Cell {
        visible: root._knownRows.length > 0
        width: parent.width

        MetaLabel { text: "KNOWN" }
    }

    Repeater {
        model: root._knownRows
        delegate: wifiRow
    }

    Cell {
        visible: root._availableRows.length > 0
        width: parent.width

        MetaLabel { text: "AVAILABLE" }
    }

    Repeater {
        model: root._availableRows
        delegate: wifiRow
    }

    Cell {
        id: speedTestCell
        width: parent.width

        Row {
            width: parent.width
            spacing: Theme.space.sm

            Text {
                width: parent.width - runToggle.width - parent.spacing
                text: "SPEED TEST"
                color: speedTestCell.foreground
                font.family: Theme.font.family
                font.pixelSize: Theme.fontSize.body
            }

            Cell {
                id: runToggle
                width: implicitWidth
                height: implicitHeight
                selected: root._stRunning

                MetaLabel {
                    text: root._stRunning ? "RUNNING…" : "RUN"
                    color: runToggle.foreground
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !root._stRunning
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._startSpeedTest()
                }
            }
        }
    }

    Cell {
        visible: root._stError !== ""
        width: parent.width

        MetaLabel { text: root._stError; color: Theme.color.urgent }
    }

    Cell {
        id: downloadCell
        visible: root._stError === "" && (root._stPhase === "down" || root._stPhase === "up" || root._stPhase === "done")
        width: parent.width

        readonly property real _mbps: root._stPhase === "down" ? root._stDownWindow.liveMbps : root._stDownResult

        Column {
            width: parent.width
            spacing: Theme.space.xxs

            Row {
                width: parent.width
                spacing: Theme.space.sm

                Text {
                    width: parent.width - downloadValue.width - parent.spacing
                    text: "DOWNLOAD"
                    color: downloadCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.body
                }

                Text {
                    id: downloadValue
                    text: SpeedTest.formatMbps(downloadCell._mbps) + " MBPS"
                    color: downloadCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.body
                }
            }

            // Flat accent fill, no thumb, no gauge: same idiom as every
            // other slider in the shell.
            Rectangle {
                width: parent.width
                height: Theme.space.trackThickness
                color: Theme.color.rule

                Rectangle {
                    width: parent.width * SpeedTest.fillFraction(downloadCell._mbps)
                    height: parent.height
                    color: Theme.color.accent
                }
            }

            MetaLabel {
                visible: root._stPhase === "down"
                text: "MEASURING DOWN…"
            }
        }
    }

    Cell {
        id: uploadCell
        visible: root._stError === "" && (root._stPhase === "up" || root._stPhase === "done")
        width: parent.width

        readonly property real _mbps: root._stPhase === "up" ? root._stUpWindow.liveMbps : root._stUpResult

        Column {
            width: parent.width
            spacing: Theme.space.xxs

            Row {
                width: parent.width
                spacing: Theme.space.sm

                Text {
                    width: parent.width - uploadValue.width - parent.spacing
                    text: "UPLOAD"
                    color: uploadCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.body
                }

                Text {
                    id: uploadValue
                    text: SpeedTest.formatMbps(uploadCell._mbps) + " MBPS"
                    color: uploadCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.body
                }
            }

            Rectangle {
                width: parent.width
                height: Theme.space.trackThickness
                color: Theme.color.rule

                Rectangle {
                    width: parent.width * SpeedTest.fillFraction(uploadCell._mbps)
                    height: parent.height
                    color: Theme.color.accent
                }
            }

            MetaLabel {
                visible: root._stPhase === "up"
                text: "MEASURING UP…"
            }
        }
    }
}

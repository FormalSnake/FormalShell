import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io
import qs.Core
import qs.Components
import qs.Services
import "../../Bluetooth/model.js" as BluetoothModel

// Bluetooth panel (DESIGN.md §Panels, spec §2, M6 Task 6; behavior parity M14
// Task 4): adapter state cell (name + state + POWER toggle, unchanged) above
// a ledger split into CONNECTED / PAIRED / AVAILABLE per Bluetooth/model.js's
// buckets(). Discovery is self-healed: while the panel is open and the
// adapter enabled, a 1s timer keeps nudging `discovering = true` whenever it
// reads false (BlueZ rejects StartDiscovery while the adapter is powering up
// and times discovery out on its own — omarchy's exact workaround,
// ~/Developer/omarchy/shell/plugins/panels/bluetooth/Panel.qml:457-464) and
// stops outright when the panel closes. Row activation: connected → pauses
// nothing, click disconnects; paired → connects; available → runs the
// pair-trust-connect sequence natively (`pair()`; once `pairedChanged`
// reports true, `trusted = true` then `connect()` — the same sequence
// omarchy shells out to bluetoothctl for, expressed with the toolkit's own
// device methods instead). One action in flight at a time, tracked at the
// panel level by address (mirrors NetworkPanel's _actionSsid/_actionKind),
// with a 20s fallback timer that clears a stuck action to an honest "TIMED
// OUT" — BluetoothDevice has no failure signal to key off, unlike
// WifiNetwork's connectionFailed, so a timeout is the only honest option for
// a pair/connect/disconnect/forget that never resolves. The in-flight
// device's own signals are watched via a single root-level Connections whose
// target tracks `_actionAddress` rather than a per-row Connections block:
// pairing/forgetting move a device between buckets exactly on the property
// change being watched, which would tear down and recreate the Repeater
// delegate holding a per-row Connections at the worst possible moment.
// forget() is the one action that Connections block can never see complete:
// it issues BlueZ's RemoveDevice, which destroys the device object outright
// rather than flipping a property on it (pinned quickshell source,
// bluez.cpp's onInterfacesRemoved: adapter->devices()->removeObject(device);
// delete device), so a successful forget leaves `_actionDevice` null with no
// paired/bonded/trustedChanged signal ever having fired — a second
// Connections block below watches the adapter's device list itself instead.
// FORGET is hover-revealed on PAIRED rows only, the same "known and not
// currently connected" restriction NetworkPanel's FORGET already applies.
//
// TRUSTED is a peer of those actions — same _runAction machinery, same
// failure surface — with one behavior difference the toolkit forces.
// BluetoothDevice::setTrusted stores its local bindable and fires
// trustedChanged BEFORE it pushes org.freedesktop.DBus.Properties.Set
// (pinned quickshell source, src/bluetooth/device.cpp:64-68), and
// DBusPropertyGroup::pushPropertyUpdate only qCWarnings a Set that comes
// back an error: it never rolls the local value back and raises no signal
// (src/dbus/properties.cpp:268-297). So `trusted` reading back as asked is
// quickshell's optimism, not BlueZ's answer, and clearing the action on it
// would paint a success nobody verified. What IS observable is a rejection —
// BlueZ pushing the old value back through the same property binding, which
// fires trustedChanged in disagreement with what was asked — so the row
// stays in flight over a short settle window that fails it on that
// disagreement, and a window elapsing without one is this action's success
// signal, the exact opposite of what actionTimeout means for
// pair/connect/disconnect/forget. The toggle is hover-revealed next to
// FORGET and only on a device BlueZ reports `paired`; the row's status line
// carries the persistent TRUSTED marker, hidden for as long as a write on
// that row is still settling.
//
// Bound directly to Quickshell.Bluetooth, same as every other panel binds
// its backend directly rather than through a Services wrapper. The test VM
// has no adapter at all, so `Bluetooth.defaultAdapter` is null and the panel
// renders the honest "NO ADAPTER" cell — the adapter-off ("TURN ON TO SCAN")
// and discovering-empty ("SCANNING…") states below it are exercised by the
// model.js bucket tests, not the smoke rig.
//
// AIRPODS NOISE (M17 Task 2): four plain action cells (OFF/ANC/
// TRANSPARENCY/ADAPTIVE) that join the same address-keyed cursor list as
// the device rows above, appended last, and appear only while
// `LibrePodsService.available` (probed once per panel open, never a poll)
// AND a connected device actually names itself AirPods
// (model.js's hasConnectedAirpods) — the socket alone only proves the
// LibrePods app is running, not that the earbuds are here.
// The protocol behind them is write-only (no D-Bus, a raw QLocalServer
// socket — see LibrePodsService.qml), so none of the four ever renders as
// selected/active; the header's dim "SET ONLY" tag is what tells the
// owner that's deliberate, not broken.
Panel {
    id: root

    panelTitle: "BLUETOOTH"
    panelWidth: Theme.space.popupWidthDefault

    readonly property var _adapter: Bluetooth.defaultAdapter
    readonly property var _devices: root._adapter ? root._adapter.devices.values : []
    readonly property var _buckets: BluetoothModel.buckets(root._devices, root._adapter ? root._adapter.discovering : false)
    readonly property var _connectedRows: root._buckets.connected
    readonly property var _pairedRows: root._buckets.known
    readonly property var _availableRows: root._buckets.available
    readonly property bool _hasAnyRows: root._connectedRows.length > 0 || root._pairedRows.length > 0 || root._availableRows.length > 0

    readonly property bool _airpodsAvailable: LibrePodsService.available && BluetoothModel.hasConnectedAirpods(root._connectedRows)
    readonly property var _airpodsModes: [
        { key: "off", label: "OFF" },
        { key: "anc", label: "ANC" },
        { key: "transparency", label: "TRANSPARENCY" },
        { key: "adaptive", label: "ADAPTIVE" }
    ]

    readonly property var _allRows: {
        var out = [];
        var i;
        for (i = 0; i < root._connectedRows.length; i++) out.push({ device: root._connectedRows[i], bucket: "connected" });
        for (i = 0; i < root._pairedRows.length; i++) out.push({ device: root._pairedRows[i], bucket: "paired" });
        for (i = 0; i < root._availableRows.length; i++) out.push({ device: root._availableRows[i], bucket: "available" });
        if (root._airpodsAvailable) {
            for (i = 0; i < root._airpodsModes.length; i++)
                out.push({ device: { address: "airpods:" + root._airpodsModes[i].key, mode: root._airpodsModes[i].key }, bucket: "airpods" });
        }
        return out;
    }

    // One action in flight at a time, keyed by device address (BlueZ's own
    // stable device identity, unlike a QML object reference that dies with
    // the delegate that briefly held it).
    property string _actionAddress: ""
    property string _actionKind: ""
    property string _failureAddress: ""
    property string _failureText: ""

    // Keyboard cursor over the combined CONNECTED+PAIRED+AVAILABLE row
    // order, tracked by address (PowerPanel's numeric _cursor doesn't fit a
    // table that splits across three headers and reshuffles rows between
    // them as actions complete — NetworkPanel's ssid-keyed cursor is the
    // same idiom, applied here by address instead).
    property string _cursorAddress: ""

    readonly property var _actionDevice: {
        if (root._actionAddress === "") return null;
        for (var i = 0; i < root._devices.length; i++) {
            if (root._devices[i].address === root._actionAddress) return root._devices[i];
        }
        return null;
    }

    onIsOpenChanged: {
        if (root.isOpen) {
            LibrePodsService.probe();
            // Cursor identity starts on the first row every open (M26 Task
            // 8's reveal-only guard below needs a real position to show,
            // never an empty address that would gate `hovered` false on the
            // first press) — empty when discovery hasn't produced a row
            // yet, which the guard's own fallback handles honestly.
            root._cursorAddress = root._allRows.length > 0 ? root._allRows[0].device.address : "";
        } else {
            root._cursorAddress = "";
            if (root._adapter)
                root._adapter.discovering = false;
        }
    }

    function _rowIndexForAddress(address) {
        for (var i = 0; i < root._allRows.length; i++) {
            if (root._allRows[i].device.address === address)
                return i;
        }
        return -1;
    }

    function _moveCursor(delta) {
        if (root._allRows.length === 0) {
            root._cursorAddress = "";
            return;
        }
        var idx = root._rowIndexForAddress(root._cursorAddress);
        if (idx < 0)
            idx = delta > 0 ? 0 : root._allRows.length - 1;
        else
            idx = Math.max(0, Math.min(root._allRows.length - 1, idx + delta));
        root._cursorAddress = root._allRows[idx].device.address;
    }

    // Panel.qml's shared keyboard-nav hook (M6 Task 7, PowerPanel's consumer
    // pattern; NetworkPanel's the direct precedent for this table-of-rows
    // shape): Up/Down move the cursor, Enter activates it.
    Connections {
        target: root

        function onKeyPressed(event) {
            if (!root.isOpen)
                return;
            // First Up/Down only reveals the cursor where it already sits
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
                root._moveCursor(-1);
                event.accepted = true;
                break;
            case Qt.Key_Down:
                root._moveCursor(1);
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                var idx = root._rowIndexForAddress(root._cursorAddress);
                if (idx >= 0)
                    root._activateRow(root._allRows[idx].bucket, root._allRows[idx].device);
                event.accepted = true;
                break;
            }
        }
    }

    function _runAction(kind, device) {
        if (root._actionKind !== "" || !device)
            return false;
        root._actionAddress = device.address;
        root._actionKind = kind;
        root._failureAddress = "";
        root._failureText = "";
        actionTimeout.restart();
        return true;
    }

    function _clearAction() {
        actionTimeout.stop();
        root._actionAddress = "";
        root._actionKind = "";
        root._failureAddress = "";
        root._failureText = "";
    }

    // Ends an in-flight action on the row it was armed for, leaving the
    // failure text behind for _statusText to render. actionTimeout's own
    // expiry lands here too, so every honest failure on this panel is
    // written in exactly one place.
    function _failAction(text) {
        actionTimeout.stop();
        root._failureAddress = root._actionAddress;
        root._failureText = text;
        root._actionAddress = "";
        root._actionKind = "";
    }

    function _checkActionCompletion(device) {
        if (!device || root._actionKind === "" || root._actionAddress !== device.address)
            return;
        if (root._actionKind === "connect" && device.connected) root._clearAction();
        else if (root._actionKind === "disconnect" && !device.connected) root._clearAction();
        else if (root._actionKind === "forget" && !device.paired && !device.bonded && !device.trusted) root._clearAction();
    }

    // Row activation (click or Enter-on-cursor): connected → disconnect;
    // paired (known) → connect; available (unpaired, discovered) → start the
    // pair-trust-connect sequence.
    function _activateRow(bucket, device) {
        if (!device || root._actionKind !== "")
            return;
        if (bucket === "airpods") {
            LibrePodsService.setNoise(device.mode);
            return;
        }
        if (bucket === "connected") {
            if (root._runAction("disconnect", device))
                device.disconnect();
            return;
        }
        if (bucket === "paired") {
            if (root._runAction("connect", device))
                device.connect();
            return;
        }
        if (root._runAction("pair", device))
            device.pair();
    }

    function _forgetDevice(device) {
        if (!device)
            return;
        if (root._runAction("forget", device))
            device.forget();
    }

    // Trust toggle (header comment carries the round-trip rationale). Only
    // BlueZ-`paired` devices are eligible, and a write that wouldn't change
    // anything is dropped before it arms the machinery: setTrusted
    // early-returns on an unchanged value (device.cpp:65), so an action
    // armed for one would sit in flight with no signal to ever answer it.
    function _setTrust(device, want) {
        if (!device || device.paired !== true || device.trusted === want)
            return;
        if (root._runAction(want ? "trust" : "untrust", device))
            device.trusted = want;
    }

    // Safety net (omarchy's pendingTimeout, Panel.qml:465-470 there): if the
    // completion signals below never fire — a pair() that BlueZ silently
    // rejects, a connect that never settles — this clears a stuck busy row
    // to an honest "TIMED OUT" instead of "PAIRING…"/"CONNECTING…" forever.
    //
    // The trust kinds run on their own clock and with the opposite meaning
    // (header comment): their window only has to outlast a BlueZ rejection
    // arriving back over the system bus, not a whole pairing handshake, and
    // elapsing without one is what CLEARS the row rather than what fails it.
    Timer {
        id: actionTimeout
        interval: (root._actionKind === "trust" || root._actionKind === "untrust") ? 2000 : 20000
        repeat: false
        onTriggered: {
            if (root._actionKind === "")
                return;
            if (root._actionKind === "trust" || root._actionKind === "untrust") {
                root._verifyTrust();
                return;
            }
            root._failAction("TIMED OUT");
        }
    }

    // Elapsing without a disagreement is NOT proof the write landed, so the
    // settle window ends in a real read-back rather than an assumption.
    // Quickshell's setTrusted stores the requested value locally and emits
    // trustedChanged BEFORE it pushes the D-Bus Set, and a Set that BlueZ
    // rejects is only qCWarning'd — no rollback, no signal (device.cpp:64-68,
    // properties.cpp:268-297). BlueZ emits no PropertiesChanged for a property
    // that never changed either, so the disagreement branch above can never
    // fire for an ordinary rejection: without this, a refused trust would
    // settle into a persistent TRUSTED marker painted purely from the
    // optimistic local value. `bluetoothctl info` reports BlueZ's own answer.
    property string _trustProbeText: ""

    function _verifyTrust() {
        var device = root._actionDevice;
        if (!device) {
            root._clearAction();
            return;
        }
        root._trustProbeText = "";
        trustProbeProc.address = device.address;
        trustProbeProc.running = true;
    }

    Process {
        id: trustProbeProc
        property string address: ""
        // Routed through `sh` so a missing bluetoothctl comes back as an
        // ordinary 127 rather than a FailedToStart that never emits `exited`
        // (src/io/process.cpp:289-297) and would strand the row busy forever.
        command: ["sh", "-c", 'command -v bluetoothctl >/dev/null 2>&1 || exit 127; exec bluetoothctl info "$1"', "sh", trustProbeProc.address]
        stdout: SplitParser {
            onRead: line => root._trustProbeText += line + "\n"
        }
        onExited: exitCode => {
            var out = root._trustProbeText;
            root._trustProbeText = "";
            if (root._actionKind !== "trust" && root._actionKind !== "untrust")
                return;
            var want = root._actionKind === "trust";
            // No bluetoothctl, or a device BlueZ no longer knows: the write's
            // outcome is genuinely unknown, and claiming either result would
            // be inventing one.
            if (exitCode !== 0) {
                root._failAction("UNVERIFIED");
                return;
            }
            var m = /^\s*Trusted:\s*(yes|no)\s*$/m.exec(out);
            if (!m) {
                root._failAction("UNVERIFIED");
                return;
            }
            if ((m[1] === "yes") === want)
                root._clearAction();
            else
                root._failAction(want ? "TRUST FAILED" : "UNTRUST FAILED");
        }
    }

    // Tracks whichever device is currently the subject of an action, rather
    // than a per-row Connections block: pairedChanged/bondedChanged both
    // fire exactly when a device relocates between buckets, which would
    // otherwise tear down the very row whose Connections needed to see the
    // signal. `pair` transitions straight into `connect` the moment BlueZ
    // reports the device paired, mirroring the trust-then-connect sequence
    // omarchy runs via bluetoothctl.
    Connections {
        target: root._actionDevice

        function onPairedChanged() {
            var device = root._actionDevice;
            if (!device)
                return;
            if (root._actionKind === "pair" && device.paired) {
                device.trusted = true;
                root._actionKind = "connect";
                actionTimeout.restart();
                device.connect();
                return;
            }
            root._checkActionCompletion(device);
        }
        function onConnectedChanged() {
            root._checkActionCompletion(root._actionDevice);
        }
        function onBondedChanged() {
            root._checkActionCompletion(root._actionDevice);
        }
        function onTrustedChanged() {
            var device = root._actionDevice;
            if (!device)
                return;
            if (root._actionKind === "trust" || root._actionKind === "untrust") {
                // Only a disagreement carries information: _setTrust's own
                // write fired this signal synchronously with the requested
                // value already stored, so agreement is the toolkit echoing
                // us back. A value that disagrees can only have come from
                // BlueZ pushing the real one in over the property binding.
                if (device.trusted !== (root._actionKind === "trust"))
                    root._failAction(root._actionKind === "trust" ? "TRUST FAILED" : "UNTRUST FAILED");
                return;
            }
            root._checkActionCompletion(device);
        }
    }

    // forget()'s completion signal: RemoveDevice deletes the device object
    // (see the header comment), so the Connections block above never fires
    // for it. adapter.devices is an ObjectModel — removeObject() emits
    // valuesChanged before the C++ delete runs, and root._devices (bound to
    // devices.values) is already reactive to that, so by the time this
    // handler runs the forgotten address is simply absent from it.
    Connections {
        target: root._adapter ? root._adapter.devices : null

        function onValuesChanged() {
            if (root._actionKind !== "forget" || root._actionAddress === "")
                return;
            for (var i = 0; i < root._devices.length; i++) {
                if (root._devices[i].address === root._actionAddress)
                    return;
            }
            root._clearAction();
        }
    }

    Component {
        id: deviceRow

        Cell {
            id: btCell
            required property var modelData
            width: parent.width
            readonly property var _device: btCell.modelData.device
            readonly property string _bucket: btCell.modelData.bucket
            readonly property string _address: btCell._device.address || ""
            readonly property bool _canForget: btCell._bucket === "paired"
            // Eligibility is BlueZ's own `paired`, not the bucket: `known`
            // also holds bonded/trusted-but-unpaired devices (model.js:73),
            // and BlueZ has nothing to trust on one of those.
            readonly property bool _canTrust: btCell._device.paired === true
            readonly property bool _isTrusted: btCell._device.trusted === true
            readonly property bool _trustPending: (root._actionKind === "trust" || root._actionKind === "untrust") && root._actionAddress === btCell._address
            selected: btCell._bucket === "connected"
            hovered: root.cursorActive && root._cursorAddress === btCell._address

            readonly property string _statusText: {
                if (root._actionKind !== "" && root._actionAddress === btCell._address) {
                    if (root._actionKind === "pair") return "PAIRING…";
                    if (root._actionKind === "connect") return "CONNECTING…";
                    if (root._actionKind === "disconnect") return "DISCONNECTING…";
                    if (root._actionKind === "trust") return "TRUSTING…";
                    if (root._actionKind === "untrust") return "UNTRUSTING…";
                    return "FORGETTING…";
                }
                if (root._failureAddress !== "" && root._failureAddress === btCell._address)
                    return root._failureText;
                return BluetoothModel.statusText(btCell._device);
            }
            readonly property bool _isFailed: root._failureAddress !== "" && root._failureAddress === btCell._address && (root._actionKind === "" || root._actionAddress !== btCell._address)

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                Item {
                    width: parent.width
                    // Read off the cells rather than actionsRow: a Cell keeps
                    // its implicit height while hidden, but a Row drops a
                    // hidden child from its own, which would leave AVAILABLE
                    // rows (neither cell eligible) shorter than the rest and
                    // break the ledger's uniform row height.
                    height: Math.max(nameText.implicitHeight, trustCell.height, forgetCell.height)

                    Text {
                        id: nameText
                        anchors.left: parent.left
                        anchors.right: actionsRow.left
                        anchors.rightMargin: actionsRow.width > 0 ? Theme.space.sm : 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: btCell._device.name || btCell._device.deviceName
                        color: btCell.foreground
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.body
                    }

                    // A Row rather than the chain of conditional anchors a
                    // second hover cell would otherwise need: TRUST and FORGET
                    // are independently eligible (see _canTrust), so every
                    // combination has to lay out without leaving a gap where
                    // the ineligible one would have been. Collapses to zero
                    // width when neither applies, which is why nameText and
                    // rowMouse can anchor to it unconditionally.
                    Row {
                        id: actionsRow
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space.sm

                        Cell {
                            id: trustCell
                            visible: btCell._canTrust
                            opacity: btCell._canTrust && btCell.hovered ? 1 : 0
                            enabled: opacity > 0 && root._actionKind === ""
                            width: implicitWidth
                            height: implicitHeight

                            Behavior on opacity {
                                NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
                            }

                            MetaLabel {
                                text: btCell._isTrusted ? "UNTRUST" : "TRUST"
                                color: btCell.foreground
                            }

                            interactive: trustCell.enabled
                            onClicked: root._setTrust(btCell._device, !btCell._isTrusted)
                        }

                        Cell {
                            id: forgetCell
                            visible: btCell._canForget
                            opacity: btCell._canForget && btCell.hovered ? 1 : 0
                            enabled: opacity > 0 && root._actionKind === ""
                            width: implicitWidth
                            height: implicitHeight

                            Behavior on opacity {
                                NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
                            }

                            MetaLabel {
                                text: "FORGET"
                                color: Theme.color.urgent
                            }

                            interactive: forgetCell.enabled
                            onClicked: root._forgetDevice(btCell._device)
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: actionsRow.left
                        enabled: root._actionKind === ""
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            root.cursorActive = true;
                            root._cursorAddress = btCell._address;
                        }
                        onClicked: root._activateRow(btCell._bucket, btCell._device)
                    }
                }

                // The status line doubles as the row's trust marker
                // (DESIGN.md §2.3's uppercase meta row): TRUSTED reports what
                // BlueZ holds, and stays hidden for as long as a write on this
                // row is inside its settle window, so the marker never asserts
                // a state the panel hasn't finished verifying.
                Row {
                    visible: btCell._statusText !== "" || (btCell._isTrusted && !btCell._trustPending)
                    width: parent.width
                    spacing: Theme.space.sm

                    Text {
                        visible: btCell._statusText !== ""
                        text: btCell._statusText
                        color: btCell._isFailed ? Theme.color.urgent : btCell.dimForeground
                        font.italic: btCell._isFailed
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.caption
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: Theme.letterSpacing.meta
                    }

                    MetaLabel {
                        visible: btCell._isTrusted && !btCell._trustPending
                        text: "TRUSTED"
                        color: btCell.dimForeground
                    }
                }
            }
        }
    }

    Cell {
        visible: !root._adapter
        width: parent.width

        MetaLabel { text: "NO ADAPTER" }
    }

    Cell {
        id: adapterCell
        visible: root._adapter !== null
        width: parent.width

        Row {
            width: parent.width
            spacing: Theme.space.sm

            Text {
                width: parent.width - powerLabel.width - parent.spacing
                // Not routed through ActionLabel/MetaLabel: the adapter's own
                // name is real device data, not ours to force uppercase (the
                // same reasoning Tooltip.qml's `verbatim` flag documents) —
                // only the trailing state word gets that treatment, via its
                // own `.toUpperCase()`. Still needs the tracking every other
                // uppercase label carries (audit "uppercase/meta treatment").
                text: root._adapter ? root._adapter.name + "  " + BluetoothAdapterState.toString(root._adapter.state).toUpperCase() : ""
                color: adapterCell.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
                font.letterSpacing: Theme.letterSpacing.meta
                elide: Text.ElideRight
            }

            // Bare-label ink promotion (DESIGN.md §1.1's 2026-08-09
            // amendment): no cell chrome, armed state promotes straight to
            // accent instead of a fill/inversion.
            MetaLabel {
                id: powerLabel
                text: "POWER"
                color: (root._adapter && root._adapter.enabled)
                    ? Theme.color.accent
                    : (powerHover.containsMouse ? Theme.color.foreground : Theme.color.foregroundDim)

                MouseArea {
                    id: powerHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root._adapter)
                            root._adapter.enabled = !root._adapter.enabled;
                    }
                }
            }
        }
    }

    // BlueZ rejects StartDiscovery while the adapter is still powering up,
    // and discovery can also lapse on its own — keep nudging it back on for
    // as long as the panel is open and the adapter enabled.
    Timer {
        id: discoveryRetry
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.isOpen && root._adapter !== null && root._adapter.enabled && !root._adapter.discovering
        onTriggered: root._adapter.discovering = true
    }

    Cell {
        visible: root._adapter !== null && !root._hasAnyRows
        width: parent.width

        MetaLabel { text: (!root._adapter || !root._adapter.enabled) ? "TURN ON TO SCAN" : "SCANNING…" }
    }

    Cell {
        visible: root._connectedRows.length > 0
        width: parent.width

        MetaLabel { text: "CONNECTED"; colon: true }
    }

    Repeater {
        model: root._connectedRows.map(function (d) { return { device: d, bucket: "connected" }; })
        delegate: deviceRow
    }

    Cell {
        visible: root._pairedRows.length > 0
        width: parent.width

        MetaLabel { text: "PAIRED"; colon: true }
    }

    Repeater {
        model: root._pairedRows.map(function (d) { return { device: d, bucket: "paired" }; })
        delegate: deviceRow
    }

    Cell {
        visible: root._availableRows.length > 0
        width: parent.width

        MetaLabel { text: "AVAILABLE"; colon: true }
    }

    Repeater {
        model: root._availableRows.map(function (d) { return { device: d, bucket: "available" }; })
        delegate: deviceRow
    }

    Cell {
        visible: root._airpodsAvailable
        width: parent.width

        Row {
            width: parent.width
            spacing: Theme.space.sm

            MetaLabel {
                width: parent.width - setOnlyLabel.width - parent.spacing
                text: "AIRPODS NOISE"
                colon: true
            }

            MetaLabel {
                id: setOnlyLabel
                text: "SET ONLY"
            }
        }
    }

    Component {
        id: airpodsModeCell

        Cell {
            id: modeCell
            required property var modelData
            readonly property string _key: modeCell.modelData.key
            readonly property string _address: "airpods:" + modeCell._key
            width: implicitWidth
            height: implicitHeight
            // These synthetic "airpods:" addresses already live in
            // `_allRows` (Enter-on-cursor routes through `_activateRow`
            // exactly like a device row), so hover joins the same shared
            // cursor `deviceRow`'s `rowMouse` writes below rather than
            // painting its own independent highlight (M26 Task 8 fix: two
            // independent hover states showed two highlights at once).
            hovered: root.cursorActive && root._cursorAddress === modeCell._address
            onContainsPointerChanged: if (modeCell.containsPointer) {
                root.cursorActive = true;
                root._cursorAddress = modeCell._address;
            }

            MetaLabel {
                text: modeCell.modelData.label
                color: modeCell.foreground
            }

            interactive: true
            onClicked: LibrePodsService.setNoise(modeCell._key)
        }
    }

    Cell {
        visible: root._airpodsAvailable
        width: parent.width

        Row {
            width: parent.width
            spacing: Theme.space.sm

            Repeater {
                model: root._airpodsModes
                delegate: airpodsModeCell
            }
        }
    }
}

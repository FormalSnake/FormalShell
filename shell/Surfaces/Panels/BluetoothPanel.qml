import QtQuick
import Quickshell.Bluetooth
import qs.Core
import qs.Components
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
// Bound directly to Quickshell.Bluetooth, same as every other panel binds
// its backend directly rather than through a Services wrapper. The test VM
// has no adapter at all, so `Bluetooth.defaultAdapter` is null and the panel
// renders the honest "NO ADAPTER" cell — the adapter-off ("TURN ON TO SCAN")
// and discovering-empty ("SCANNING…") states below it are exercised by the
// model.js bucket tests, not the smoke rig.
Panel {
    id: root

    panelTitle: "BLUETOOTH"

    readonly property var _adapter: Bluetooth.defaultAdapter
    readonly property var _devices: root._adapter ? root._adapter.devices.values : []
    readonly property var _buckets: BluetoothModel.buckets(root._devices, root._adapter ? root._adapter.discovering : false)
    readonly property var _connectedRows: root._buckets.connected
    readonly property var _pairedRows: root._buckets.known
    readonly property var _availableRows: root._buckets.available
    readonly property bool _hasAnyRows: root._connectedRows.length > 0 || root._pairedRows.length > 0 || root._availableRows.length > 0

    readonly property var _allRows: {
        var out = [];
        var i;
        for (i = 0; i < root._connectedRows.length; i++) out.push({ device: root._connectedRows[i], bucket: "connected" });
        for (i = 0; i < root._pairedRows.length; i++) out.push({ device: root._pairedRows[i], bucket: "paired" });
        for (i = 0; i < root._availableRows.length; i++) out.push({ device: root._availableRows[i], bucket: "available" });
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
        if (!root.isOpen) {
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

    // Safety net (omarchy's pendingTimeout, Panel.qml:465-470 there): if the
    // completion signals below never fire — a pair() that BlueZ silently
    // rejects, a connect that never settles — this clears a stuck busy row
    // to an honest "TIMED OUT" instead of "PAIRING…"/"CONNECTING…" forever.
    Timer {
        id: actionTimeout
        interval: 20000
        repeat: false
        onTriggered: {
            if (root._actionKind === "")
                return;
            root._failureAddress = root._actionAddress;
            root._failureText = "TIMED OUT";
            root._actionAddress = "";
            root._actionKind = "";
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
            root._checkActionCompletion(root._actionDevice);
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
            selected: btCell._bucket === "connected"
            hovered: rowMouse.containsMouse || forgetMouse.containsMouse || (root._cursorAddress !== "" && root._cursorAddress === btCell._address)

            readonly property string _statusText: {
                if (root._actionKind !== "" && root._actionAddress === btCell._address) {
                    if (root._actionKind === "pair") return "PAIRING…";
                    if (root._actionKind === "connect") return "CONNECTING…";
                    if (root._actionKind === "disconnect") return "DISCONNECTING…";
                    return "FORGETTING…";
                }
                if (root._failureAddress !== "" && root._failureAddress === btCell._address)
                    return root._failureText;
                return BluetoothModel.statusText(btCell._device);
            }
            readonly property bool _isFailed: root._failureAddress !== "" && root._failureAddress === btCell._address && (root._actionKind === "" || root._actionAddress !== btCell._address)

            Column {
                width: parent.width
                spacing: Theme.spacing.xs

                Item {
                    width: parent.width
                    height: Math.max(nameText.implicitHeight, forgetCell.height)

                    Text {
                        id: nameText
                        anchors.left: parent.left
                        anchors.right: btCell._canForget ? forgetCell.left : parent.right
                        anchors.rightMargin: btCell._canForget ? Theme.spacing.sm : 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: btCell._device.name || btCell._device.deviceName
                        color: btCell.foreground
                        elide: Text.ElideRight
                        font.family: Theme.font.family
                        font.pixelSize: Theme.fontSize.body
                    }

                    Cell {
                        id: forgetCell
                        visible: btCell._canForget
                        opacity: btCell._canForget && btCell.hovered ? 1 : 0
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
                            onClicked: root._forgetDevice(btCell._device)
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: btCell._canForget ? forgetCell.left : parent.right
                        enabled: root._actionKind === ""
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._activateRow(btCell._bucket, btCell._device)
                    }
                }

                Text {
                    visible: btCell._statusText !== ""
                    text: btCell._statusText
                    color: btCell._isFailed ? Theme.color.urgent : btCell.foreground
                    font.italic: btCell._isFailed
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.caption
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
            spacing: Theme.spacing.sm

            Text {
                width: parent.width - powerCell.width - parent.spacing
                text: root._adapter ? root._adapter.name + "  " + BluetoothAdapterState.toString(root._adapter.state).toUpperCase() : ""
                color: adapterCell.foreground
                font.family: Theme.font.family
                font.pixelSize: Theme.fontSize.body
                elide: Text.ElideRight
            }

            Cell {
                id: powerCell
                width: implicitWidth
                height: implicitHeight
                selected: root._adapter ? root._adapter.enabled : false

                MetaLabel {
                    text: "POWER"
                    color: powerCell.foreground
                }

                MouseArea {
                    anchors.fill: parent
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

        MetaLabel { text: "CONNECTED" }
    }

    Repeater {
        model: root._connectedRows.map(function (d) { return { device: d, bucket: "connected" }; })
        delegate: deviceRow
    }

    Cell {
        visible: root._pairedRows.length > 0
        width: parent.width

        MetaLabel { text: "PAIRED" }
    }

    Repeater {
        model: root._pairedRows.map(function (d) { return { device: d, bucket: "paired" }; })
        delegate: deviceRow
    }

    Cell {
        visible: root._availableRows.length > 0
        width: parent.width

        MetaLabel { text: "AVAILABLE" }
    }

    Repeater {
        model: root._availableRows.map(function (d) { return { device: d, bucket: "available" }; })
        delegate: deviceRow
    }
}

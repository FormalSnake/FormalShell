import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io
import qs.Core
import qs.Components
import "../../Bluetooth/model.js" as BluetoothModel

// Bluetooth panel (DESIGN.md §3 "Panel", spec "Panels"): the header carries
// the adapter's power `Switch` and a rescan button, the hero names the one
// connected device (or the adapter itself), and the rows split into
// `PAIRED (n)` (connected first, each carrying a check) and `AVAILABLE (n)`.
// Tab moves between those two lists, Enter connects or disconnects the row
// under the cursor, and `x` forgets a paired one.
//
// Discovery is self-healed: while the panel is open and the adapter enabled,
// a 1s timer keeps nudging `discovering = true` whenever it reads false
// (BlueZ rejects StartDiscovery while the adapter is powering up and times
// discovery out on its own, omarchy's exact workaround,
// ~/Developer/omarchy/shell/plugins/panels/bluetooth/Panel.qml:457-464) and
// stops outright when the panel closes. Row activation: connected
// disconnects; paired connects; available runs the pair-trust-connect
// sequence natively (`pair()`; once `pairedChanged` reports true,
// `trusted = true` then `connect()`, the same sequence omarchy shells out to
// bluetoothctl for, expressed with the toolkit's own device methods
// instead). One action in flight at a time, tracked at the panel level by
// address (mirrors NetworkPanel's _actionSsid/_actionKind), with a 20s
// fallback timer that clears a stuck action to an honest "TIMED OUT":
// BluetoothDevice has no failure signal to key off, unlike WifiNetwork's
// connectionFailed, so a timeout is the only honest option for a
// pair/connect/disconnect/forget that never resolves. The in-flight device's
// own signals are watched via a single root-level Connections whose target
// tracks `_actionAddress` rather than a per-row Connections block:
// pairing/forgetting move a device between buckets exactly on the property
// change being watched, which would tear down and recreate the Repeater
// delegate holding a per-row Connections at the worst possible moment.
// forget() is the one action that Connections block can never see complete:
// it issues BlueZ's RemoveDevice, which destroys the device object outright
// rather than flipping a property on it (pinned quickshell source,
// bluez.cpp's onInterfacesRemoved: adapter->devices()->removeObject(device);
// delete device), so a successful forget leaves `_actionDevice` null with no
// paired/bonded/trustedChanged signal ever having fired: a second
// Connections block below watches the adapter's device list itself instead.
// Forget is offered on paired rows only, the same "known and not currently
// connected" restriction NetworkPanel's own forget applies.
//
// AirPods noise control lives in AirpodsPanel (M29 Task 2), which owns the
// daemon this panel used to talk to.
//
// TRUST is a peer of those actions (same _runAction machinery, same failure
// surface) with one behavior difference the toolkit forces.
// BluetoothDevice::setTrusted stores its local bindable and fires
// trustedChanged BEFORE it pushes org.freedesktop.DBus.Properties.Set
// (pinned quickshell source, src/bluetooth/device.cpp:64-68), and
// DBusPropertyGroup::pushPropertyUpdate only qCWarnings a Set that comes
// back an error: it never rolls the local value back and raises no signal
// (src/dbus/properties.cpp:268-297). So `trusted` reading back as asked is
// quickshell's optimism, not BlueZ's answer, and clearing the action on it
// would paint a success nobody verified. What IS observable is a rejection,
// BlueZ pushing the old value back through the same property binding, which
// fires trustedChanged in disagreement with what was asked, so the row stays
// in flight over a short settle window that fails it on that disagreement,
// and a window elapsing without one is this action's success signal, the
// exact opposite of what actionTimeout means for
// pair/connect/disconnect/forget. The toggle sits beside forget and only on
// a device BlueZ reports `paired`; the row's status line carries the
// persistent TRUSTED marker, hidden for as long as a write on that row is
// still settling.
//
// Bound directly to Quickshell.Bluetooth, same as every other panel binds
// its backend directly rather than through a Services wrapper. The test VM
// has no adapter at all, so `Bluetooth.defaultAdapter` is null and the panel
// renders the honest "NO ADAPTER" row; the adapter-off ("TURN ON TO SCAN")
// and discovering-empty ("SCANNING…") states below it are exercised by the
// model.js bucket tests, not the smoke rig.
Panel {
    id: root

    panelIcon: "bluetooth"
    panelTitle: "Bluetooth"
    panelWidth: Theme.space.popupWidthDefault

    readonly property var _adapter: Bluetooth.defaultAdapter
    readonly property var _devices: root._adapter ? root._adapter.devices.values : []
    readonly property var _buckets: BluetoothModel.buckets(root._devices, root._adapter ? root._adapter.discovering : false)
    readonly property var _connectedRows: root._buckets.connected
    readonly property var _pairedRows: root._buckets.known
    readonly property var _availableRows: root._buckets.available
    readonly property bool _hasAnyRows: root._pairedSection.length > 0 || root._availableSection.length > 0

    // The hero's own subject (M28 Task 5): the one connected device when
    // there is exactly one, else the adapter's own name. A specific
    // connected device is only named when it is unambiguous which one, so
    // two simultaneous connections (a mouse and a headset, say) fall back to
    // naming the radio itself rather than picking one arbitrarily.
    readonly property var _heroDevice: root._connectedRows.length === 1 ? root._connectedRows[0] : null
    readonly property string _heroTitle: root._heroDevice
        ? (root._heroDevice.name || root._heroDevice.deviceName)
        : (root._adapter ? root._adapter.name : "")
    readonly property string _heroMeta: root._heroDevice
        ? (BluetoothModel.activityText(root._heroDevice) || "CONNECTED")
        : (root._adapter ? BluetoothAdapterState.toString(root._adapter.state).toUpperCase() : "")
    readonly property string _heroBattery: root._heroDevice ? BluetoothModel.batteryText(root._heroDevice) : ""
    readonly property string _heroIcon: (!root._adapter || !root._adapter.enabled)
        ? "bluetooth-off"
        : (root._connectedRows.length > 0 ? "bluetooth-connected" : "bluetooth")

    // Connected devices lead the paired list rather than forming a third
    // section: they are the same "this machine knows this device" set, and
    // the check on the row already says which one is live.
    readonly property var _pairedSection: {
        var out = [];
        var i;
        for (i = 0; i < root._connectedRows.length; i++)
            out.push({ device: root._connectedRows[i], bucket: "connected", section: 0 });
        for (i = 0; i < root._pairedRows.length; i++)
            out.push({ device: root._pairedRows[i], bucket: "paired", section: 0 });
        return out;
    }
    readonly property var _availableSection: root._availableRows.map(function (d) {
        return { device: d, bucket: "available", section: 1 };
    })

    // The rows Tab has reached: Panel's cursor addresses one list at a time.
    readonly property var _sectionRows: root.cursorSection === 1 ? root._availableSection : root._pairedSection

    // One action in flight at a time, keyed by device address (BlueZ's own
    // stable device identity, unlike a QML object reference that dies with
    // the delegate that briefly held it).
    property string _actionAddress: ""
    property string _actionKind: ""
    property string _failureAddress: ""
    property string _failureText: ""

    // The cursor's row identity, kept alongside Panel's own numeric
    // cursorIndex: rows relocate between buckets as actions complete, and an
    // index on its own would walk the cursor onto whatever slid underneath.
    property string _cursorAddress: ""

    readonly property var _actionDevice: {
        if (root._actionAddress === "") return null;
        for (var i = 0; i < root._devices.length; i++) {
            if (root._devices[i].address === root._actionAddress) return root._devices[i];
        }
        return null;
    }

    function _rowAt(index) {
        return (index >= 0 && index < root._sectionRows.length) ? root._sectionRows[index] : null;
    }

    function _addressAt(index) {
        var row = root._rowAt(index);
        return row ? (row.device.address || "") : "";
    }

    function _indexForAddress(address) {
        for (var i = 0; i < root._sectionRows.length; i++) {
            if ((root._sectionRows[i].device.address || "") === address)
                return i;
        }
        return -1;
    }

    function _pointAt(section, address) {
        root.cursorActive = true;
        root.cursorSection = section;
        var index = root._indexForAddress(address);
        if (index >= 0)
            root.cursorIndex = index;
    }

    cursorCount: root._sectionRows.length
    // 0 is PAIRED, 1 is AVAILABLE.
    sectionCount: 2

    onCursorIndexChanged: root._cursorAddress = root._addressAt(root.cursorIndex)

    onCursorSectionChanged: {
        root.cursorIndex = 0;
        root._cursorAddress = root._addressAt(0);
    }

    on_SectionRowsChanged: {
        var index = root._indexForAddress(root._cursorAddress);
        if (index >= 0 && index !== root.cursorIndex)
            root.cursorIndex = index;
    }

    onCursorActivated: index => {
        var row = root._rowAt(index);
        if (row)
            root._activateRow(row.bucket, row.device);
    }

    onCursorDeleted: index => {
        var row = root._rowAt(index);
        if (row && row.bucket === "paired")
            root._forgetDevice(row.device);
    }

    onIsOpenChanged: {
        if (root.isOpen) {
            // The cursor starts on the first row every open, so the
            // reveal-only first keypress has a real position to show. Empty
            // while discovery has produced nothing yet.
            root.cursorIndex = 0;
            root.cursorSection = 0;
            root._cursorAddress = root._addressAt(0);
        } else {
            root._cursorAddress = "";
            if (root._adapter)
                root._adapter.discovering = false;
        }
    }

    // The adapter's power is an on/off state, so it is a `Switch`
    // (DESIGN.md §2); rescan is one action, so it stays an `IconButton`
    // beside it.
    titleActions: [
        Switch {
            checked: root._adapter !== null && root._adapter.enabled
            enabled: root._adapter !== null
            onToggled: checked => { if (root._adapter) root._adapter.enabled = checked; }
        },
        IconButton {
            name: "refresh-cw"
            tooltipText: "Rescan"
            enabled: root._adapter !== null && root._adapter.enabled
            onClicked: root._rescan()
        }
    ]

    // Dropping discovery and letting discoveryRetry below re-arm it is the
    // rescan handle BlueZ gives: StartDiscovery on an already-discovering
    // adapter is a no-op, so restarting the scan means stopping it first.
    function _rescan() {
        if (!root._adapter)
            return;
        root._adapter.discovering = false;
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
    // failure text behind for the row's status line. actionTimeout's own
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

    // Row activation (click or Enter-on-cursor): connected disconnects;
    // paired (known) connects; available (unpaired, discovered) starts the
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
    // completion signals below never fire (a pair() that BlueZ silently
    // rejects, a connect that never settles) this clears a stuck busy row to
    // an honest "TIMED OUT" instead of "PAIRING…"/"CONNECTING…" forever.
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
    // rejects is only qCWarning'd: no rollback, no signal (device.cpp:64-68,
    // properties.cpp:268-297). BlueZ emits no PropertiesChanged for a property
    // that never changed either, so the disagreement branch below can never
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
    // for it. adapter.devices is an ObjectModel, removeObject() emits
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

    // BlueZ rejects StartDiscovery while the adapter is still powering up,
    // and discovery can also lapse on its own: keep nudging it back on for
    // as long as the panel is open and the adapter enabled.
    Timer {
        id: discoveryRetry
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.isOpen && root._adapter !== null && root._adapter.enabled && !root._adapter.discovering
        onTriggered: root._adapter.discovering = true
    }

    Component {
        id: deviceRow

        Cell {
            id: btCell
            required property var modelData
            width: parent.width
            ghost: true
            interactive: root._actionKind === ""

            readonly property var _device: btCell.modelData.device
            readonly property string _bucket: btCell.modelData.bucket
            readonly property int _section: btCell.modelData.section
            readonly property string _address: btCell._device.address || ""
            readonly property bool _connected: btCell._bucket === "connected"
            readonly property bool _canForget: btCell._bucket === "paired"
            // Eligibility is BlueZ's own `paired`, not the bucket: `known`
            // also holds bonded/trusted-but-unpaired devices (model.js:73),
            // and BlueZ has nothing to trust on one of those.
            readonly property bool _canTrust: btCell._device.paired === true
            readonly property bool _isTrusted: btCell._device.trusted === true
            readonly property bool _trustPending: (root._actionKind === "trust" || root._actionKind === "untrust") && root._actionAddress === btCell._address
            readonly property string _battery: BluetoothModel.batteryText(btCell._device)
            readonly property bool _revealed: btCell.hovered || btCell.cursor

            cursor: root.cursorActive && root.cursorSection === btCell._section && root._cursorAddress === btCell._address

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
                var activity = BluetoothModel.activityText(btCell._device);
                if (activity !== "")
                    return activity;
                // The persistent marker reports what BlueZ holds, and stays
                // hidden for as long as a write on this row is inside its
                // settle window, so it never asserts a state the panel
                // hasn't finished verifying.
                return (btCell._isTrusted && !btCell._trustPending) ? "TRUSTED" : "";
            }
            readonly property bool _isFailed: root._failureAddress !== "" && root._failureAddress === btCell._address && (root._actionKind === "" || root._actionAddress !== btCell._address)

            onContainsPointerChanged: if (btCell.containsPointer) root._pointAt(btCell._section, btCell._address)

            onClicked: root._activateRow(btCell._bucket, btCell._device)

            Column {
                width: parent.width
                spacing: Theme.space.xs

                Item {
                    width: parent.width
                    height: nameText.implicitHeight

                    Icon {
                        id: rowIcon
                        name: btCell._connected ? "bluetooth-connected" : "bluetooth"
                        size: Theme.fontSize.body
                        color: btCell.foreground
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        id: nameText
                        anchors.left: rowIcon.right
                        anchors.leftMargin: Theme.space.iconGap
                        anchors.right: trailingBits.left
                        anchors.rightMargin: Theme.space.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        text: btCell._device.name || btCell._device.deviceName
                        color: btCell.foreground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                        elide: Text.ElideRight
                    }

                    Row {
                        id: trailingBits
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space.iconGap

                        Text {
                            visible: btCell._battery !== ""
                            text: btCell._battery
                            color: btCell.dimForeground
                            font.family: Theme.fontFamilyMono
                            font.pixelSize: Theme.fontSize.bodySmall
                        }

                        SectionLabel {
                            id: trustLabel
                            visible: btCell._canTrust
                            opacity: btCell._revealed ? 1 : 0
                            text: btCell._isTrusted ? "UNTRUST" : "TRUST"
                            color: trustHit.containsMouse ? Theme.color.foreground : btCell.dimForeground

                            Behavior on opacity {
                                NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
                            }

                            // Sits above the cell's own pointer layer, so the
                            // trust hit never doubles as a row activation.
                            MouseArea {
                                id: trustHit
                                anchors.fill: parent
                                anchors.margins: -Theme.space.xs
                                enabled: trustLabel.opacity > 0 && root._actionKind === ""
                                hoverEnabled: enabled
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._setTrust(btCell._device, !btCell._isTrusted)
                            }
                        }

                        Icon {
                            id: forgetIcon
                            name: "trash"
                            size: Theme.fontSize.body
                            visible: btCell._canForget
                            opacity: btCell._revealed ? 1 : 0
                            color: forgetHit.containsMouse ? Theme.color.destructive : btCell.dimForeground

                            Behavior on opacity {
                                NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
                            }

                            // The negative margins buy back a hit area a
                            // 13px glyph cannot offer on its own.
                            MouseArea {
                                id: forgetHit
                                anchors.fill: parent
                                anchors.margins: -Theme.space.sm
                                enabled: forgetIcon.opacity > 0 && root._actionKind === ""
                                hoverEnabled: enabled
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._forgetDevice(btCell._device)
                            }
                        }

                        Icon {
                            name: "check"
                            size: Theme.fontSize.body
                            visible: btCell._connected
                            color: Theme.color.primary
                        }
                    }
                }

                SectionLabel {
                    visible: btCell._statusText !== ""
                    text: btCell._statusText
                    color: btCell._isFailed ? Theme.color.destructive : btCell.dimForeground
                    font.italic: btCell._isFailed
                }
            }
        }
    }

    SectionLabel {
        visible: !root._adapter
        leftPadding: Theme.space.controlPaddingX
        text: "NO ADAPTER"
    }

    // The panel's own subject (M28 Task 5): the one connected device, or
    // the adapter itself. Power moved to the header's own toggle.
    PanelHero {
        id: hero
        visible: root._adapter !== null
        width: parent.width
        title: root._heroTitle
        meta: root._heroMeta

        leading: Component {
            Icon {
                name: root._heroIcon
                size: Theme.fontSize.heading
                color: hero.foreground
            }
        }

        trailing: Component {
            Text {
                visible: root._heroBattery !== ""
                text: root._heroBattery
                color: hero.dimForeground
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSize.bodySmall
            }
        }
    }

    SectionLabel {
        visible: root._adapter !== null && !root._hasAnyRows
        leftPadding: Theme.space.controlPaddingX
        text: (!root._adapter || !root._adapter.enabled) ? "TURN ON TO SCAN" : "SCANNING…"
    }

    Column {
        width: parent.width
        visible: root._pairedSection.length > 0
        spacing: Theme.space.rowGap

        SectionLabel {
            leftPadding: Theme.space.controlPaddingX
            text: "PAIRED"
            count: root._pairedSection.length
        }

        // A borderless row leaves no box for a gap to sit between, so the rows
        // in a section abut and only `sectionGap` separates the sections.
        Column {
            width: parent.width
            spacing: 0

            Repeater {
                model: root._pairedSection
                delegate: deviceRow
            }
        }
    }

    Column {
        width: parent.width
        visible: root._availableSection.length > 0
        spacing: Theme.space.rowGap

        SectionLabel {
            leftPadding: Theme.space.controlPaddingX
            text: "AVAILABLE"
            count: root._availableSection.length
        }

        Column {
            width: parent.width
            spacing: 0

            Repeater {
                model: root._availableSection
                delegate: deviceRow
            }
        }
    }
}

import QtQuick
import qs.Compositor
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "../../Audio/model.js" as AudioModel
import qs.Services
import "../../Bluetooth/model.js" as BluetoothModel
import "../../Network/model.js" as NetworkModel

// The clipboard and window lists behind the menu's clipboard/apps
// providers, mirrored ONLY while the menu is actually open (M17 review
// finding, M-polish batch item G, owner: low-end laptop): `active` gates
// both ternaries below, so a capture or a window event landing while the
// menu is closed touches nothing here at all. The moment `active` flips
// true both re-read the live state and resubscribe, so content is exactly
// as fresh as before for as long as the menu stays open.
Item {
    id: root

    // Bound to Menu.qml's isOpen.
    property bool active: false

    // The bluetooth route's rows are built from this, only while active and
    // only republished when the fields the rows read change.
    readonly property var bluetooth: root.active ? root._btLive : root._btIdle
    readonly property var _btIdle: ({ available: false, enabled: false, devices: [] })
    property var _btLive: root._btIdle
    property string _btKey: ""

    // Addresses of the connected Bluetooth devices, the source of the
    // `bluetooth.connected` tick list.
    readonly property var bluetoothConnected: root.bluetooth.connected || []

    readonly property var _btNow: root.active ? root._btState() : null

    function _btState() {
        var adapter = Bluetooth.defaultAdapter;
        if (!adapter)
            return { available: false, enabled: false, devices: [], connected: [] };
        var values = adapter.devices.values;
        var devices = [];
        for (var i = 0; i < values.length; i++) {
            var d = values[i];
            devices.push({
                address: d.address,
                name: d.name,
                deviceName: d.deviceName,
                connected: d.connected,
                paired: d.paired,
                bonded: d.bonded,
                trusted: d.trusted,
                activity: BluetoothModel.activityText(d),
                battery: BluetoothModel.batteryText(d)
            });
        }
        return { available: true, enabled: adapter.enabled, devices: devices, connected: BluetoothModel.connectedAddresses(values) };
    }

    on_BtNowChanged: {
        if (!root._btNow)
            return;
        var key = JSON.stringify(root._btNow);
        if (key === root._btKey)
            return;
        root._btKey = key;
        root._btLive = root._btNow;
    }

    // The radio route's rows; republished only when a favourite's name or
    // country, or whether a station is tuned, changes.
    readonly property var radio: root.active ? root._radioLive : root._radioIdle
    readonly property var _radioIdle: ({ favorites: [], running: false })
    property var _radioLive: root._radioIdle
    property string _radioKey: ""

    readonly property var _radioNow: root.active ? {
        favorites: RadioService.favorites.map(function (s) { return { uuid: s.uuid, name: s.name, country: s.country }; }),
        running: RadioService.running
    } : null

    on_RadioNowChanged: {
        if (!root._radioNow)
            return;
        var key = JSON.stringify(root._radioNow);
        if (key === root._radioKey)
            return;
        root._radioKey = key;
        root._radioLive = root._radioNow;
    }

    // The audio route's rows; republished only when the device set changes.
    readonly property var audioDevices: root.active ? root._audioLive : []
    property var _audioLive: []
    property string _audioKey: ""

    readonly property var _audioNow: root.active ? AudioModel.deviceRows(Pipewire.nodes.values) : null

    on_AudioNowChanged: {
        if (!root._audioNow)
            return;
        var key = JSON.stringify(root._audioNow);
        if (key === root._audioKey)
            return;
        root._audioKey = key;
        root._audioLive = root._audioNow;
    }

    // The wifi route's rows are built from this, only while active and only
    // republished when something other than signal strength changed. Signal
    // only feeds the sort, so a strength tick alone never rebuilds the tree.
    readonly property var wifi: root.active ? root._wifiLive : root._wifiIdle
    readonly property var _wifiIdle: ({ hasDevice: false, enabled: false, networks: [], actionSsid: "", actionKind: "", failureSsid: "", failureText: "" })
    property var _wifiLive: root._wifiIdle
    property string _wifiKey: ""

    readonly property var _wifiNow: root.active ? root._wifiState() : null

    function _wifiState() {
        return {
            hasDevice: WifiService.hasDevice,
            enabled: WifiService.enabled,
            networks: WifiService.networks.map(function (n) {
                return {
                    name: n.name || "",
                    known: n.known,
                    connected: n.connected,
                    secured: NetworkModel.isSecured(n.security),
                    enterprise: NetworkModel.isEnterprise(n.security),
                    signal: n.signalStrength
                };
            }),
            actionSsid: WifiService.actionSsid,
            actionKind: WifiService.actionKind,
            failureSsid: WifiService.failureSsid,
            failureText: WifiService.failureText
        };
    }

    on_WifiNowChanged: {
        if (!root._wifiNow)
            return;
        var key = JSON.stringify(root._wifiNow, function (k, v) { return k === "signal" ? undefined : v; });
        if (key === root._wifiKey)
            return;
        root._wifiKey = key;
        root._wifiLive = root._wifiNow;
    }

    readonly property var clipboardItems: root.active ? ClipboardService.items : []

    // Prerender the ledger's image captures the moment the live list
    // resolves, `fit` rather than the picker's `cover` (MenuRow's own thumb
    // slot letterboxes). Gated behind `active` by construction, since
    // clipboardItems is empty while closed, so a capture landing on a
    // closed launcher warms nothing. A ledger of text entries warms nothing
    // either: the filter is what decides there is work at all.
    // `kind`/`path` are the service's own field names; `thumbSource` is what
    // clipboardProvider renames `path` to on the row it builds, and this
    // reads the service rather than the rows so it does not wait on a tree
    // rebuild to notice a new capture.
    onClipboardItemsChanged: {
        var images = (root.clipboardItems || []).filter(function (item) {
            return item && item.kind === "image" && (item.path || "") !== "";
        }).map(function (item) { return item.path; });
        ThumbnailService.warm(images, "fit");
    }

    // The same gate, for the same reason, on the compositor's window list.
    // The apps provider decorates each app row with its running windows,
    // and it reads this inside the tree's own binding, so an ungated read
    // subscribed the whole tree to every window open, close AND TITLE
    // CHANGE: a browser tab switch rebuilt the JSONC merge, every provider,
    // the frecency sort and a Quickshell.iconPath call per installed app,
    // with the launcher closed and nobody looking. Closed, the app rows
    // carry no window matches, which is exactly as observable as the
    // clipboard being empty up there.
    //
    // Even while active, `_windowsLive` below is kept apart from a raw
    // CompositorService.windows binding: appmatch.js only ever compares
    // `id` and `appId` (never title), so it is republished only when that
    // pair changes for some window, and a title-only tick (a browser tab
    // switch, again) leaves the array's identity alone instead of rebuilding
    // the tree under whoever is typing in the launcher.
    readonly property var windows: root.active ? root._windowsLive : []

    property var _windowsLive: []
    property string _windowsKey: ""

    function _update() {
        var windowList = CompositorService.windows || [];
        var pairs = [];
        for (var i = 0; i < windowList.length; i++) {
            var w = windowList[i] || {};
            pairs.push((w.id || "") + "\0" + (w.appId || ""));
        }
        var key = JSON.stringify(pairs);
        if (key === root._windowsKey)
            return;
        root._windowsKey = key;
        root._windowsLive = windowList;
    }

    onActiveChanged: if (root.active) root._update()

    // Enabled only while active, mirroring the ternary above: a windows
    // tick while closed must cost nothing, the same guarantee the raw-
    // binding form gave for free by simply not reading
    // CompositorService.windows in the branch that isn't taken.
    Connections {
        target: CompositorService
        enabled: root.active
        function onWindowsChanged() { root._update(); }
    }
}

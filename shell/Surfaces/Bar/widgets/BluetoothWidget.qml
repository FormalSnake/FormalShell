import QtQuick
import Quickshell.Bluetooth
import qs.Core
import qs.Components

// Bar cell for bluetooth status (DESIGN.md §Bar's "network/BT glyphs"
// indicator slot, spec §1, M6 Task 6): a single glyph for adapter/device
// state (no adapter or disabled, enabled with nothing connected, enabled
// with a device connected), click toggles the bluetooth panel anchored
// under this cell — same panel-open accent dot idiom as NetworkWidget.qml.
// Glyph codepoints taken from the pinned nerd-fonts-jetbrains-mono cmap
// (nix/testvm.nix): md-bluetooth U+F00AF, md-bluetooth_connect U+F00B1,
// md-bluetooth_off U+F00B2.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    readonly property var _adapter: Bluetooth.defaultAdapter
    // BluetoothPanel.qml's own device-row accessor (`name || deviceName`):
    // `name` is the alias the user may have set, `deviceName` the one the
    // device reports for itself.
    readonly property var _connectedNames: root._adapter
        ? root._adapter.devices.values
            .filter(function (d) { return d.connected; })
            .map(function (d) { return d.name || d.deviceName; })
        : []
    readonly property bool _connected: root._connectedNames.length > 0
    readonly property string _glyph: (!root._adapter || !root._adapter.enabled)
        ? "󰂲"
        : (root._connected ? "󰂱" : "󰂯")

    standalone: true

    // Three glyphs cover four states between them (no adapter and adapter
    // off share one), and none of them names the device that's connected.
    // "NO ADAPTER"/"NO DEVICES" are BluetoothPanel.qml's own honest-empty
    // strings, not second wordings for the same states.
    tooltipText: {
        if (!root._adapter)
            return "BLUETOOTH / NO ADAPTER";
        if (!root._adapter.enabled)
            return "BLUETOOTH / OFF";
        if (root._connectedNames.length === 0)
            return "BLUETOOTH / NO DEVICES";
        return "BLUETOOTH / " + root._connectedNames.join(", ");
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root._glyph
        color: root.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize.body
    }

    PanelOpenDot {
        visible: root._panelOpen
        inverted: root.invertedNow
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
    }

    interactive: true
    onClicked: {
        if (root.panel)
            root.panel.toggle(root.mapToItem(null, 0, 0).x);
    }
}

import QtQuick
import Quickshell.Bluetooth
import qs.Core
import qs.Components

// Bar cell for bluetooth status (DESIGN.md §3 Bar, spec "Surfaces"): one
// icon for adapter/device state (no adapter or disabled, enabled with
// nothing connected, enabled with a device connected), click toggles the
// bluetooth panel anchored under this cell, same open-panel line as
// NetworkWidget.qml.
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
    readonly property string _icon: (!root._adapter || !root._adapter.enabled)
        ? "bluetooth-off"
        : (root._connected ? "bluetooth-connected" : "bluetooth")

    // Three icons cover four states between them (no adapter and adapter
    // off share one), and none of them names the device that's connected.
    // "NO ADAPTER"/"NO DEVICES" are BluetoothPanel.qml's own honest-empty
    // strings, not second wordings for the same states. The trailing
    // segment states the M26 Task 9 right-click action: no adapter means
    // there's nothing to toggle, so it's omitted rather than dangled.
    tooltipText: {
        if (!root._adapter)
            return "BLUETOOTH / NO ADAPTER";
        var head;
        if (!root._adapter.enabled)
            head = "BLUETOOTH / OFF";
        else if (root._connectedNames.length === 0)
            head = "BLUETOOTH / NO DEVICES";
        else
            head = "BLUETOOTH / " + root._connectedNames.join(", ");
        return head + " / RIGHT " + (root._adapter.enabled ? "RADIO OFF" : "RADIO ON");
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: root._icon
        color: root.foreground
    }

    panelOpen: root._panelOpen

    interactive: true
    // M26 Task 9: right click toggles the adapter radio, middle also opens
    // the panel (upstream's redundant left/middle idiom, `manual/
    // 05-the-top-bar.md`'s Audio row).
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            if (root._adapter)
                root._adapter.enabled = !root._adapter.enabled;
        } else if (root.panel) {
            root.panel.toggleFrom(root);
        }
    }
}

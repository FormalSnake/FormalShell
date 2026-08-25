import QtQuick
import Quickshell.Networking
import qs.Core
import qs.Components

// Bar cell for network status (DESIGN.md §3 Bar, spec §1, M6 Task 6): one
// icon for the strongest active connection (wired beats wifi beats
// disconnected), click toggles the network panel anchored under this
// cell, same open-panel underline as AudioWidget.qml/Clock.qml.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    readonly property var _devices: Networking.devices.values
    readonly property bool _wiredConnected: root._devices.some(function (d) {
        return d.type === DeviceType.Wired && d.connected;
    })
    readonly property bool _wifiConnected: root._devices.some(function (d) {
        return d.type === DeviceType.Wifi && d.connected;
    })
    readonly property string _icon: root._wiredConnected
        ? "globe"
        : (root._wifiConnected ? "wifi" : "wifi-off")

    // The connected network behind the wifi glyph, if NetworkManager has one
    // to name — NetworkDevice.networks carries the device's own scan list,
    // of which at most one is `connected` at a time.
    readonly property var _activeWifi: {
        for (var i = 0; i < root._devices.length; i++) {
            var device = root._devices[i];
            if (device.type !== DeviceType.Wifi || !device.connected)
                continue;
            var networks = device.networks.values;
            for (var j = 0; j < networks.length; j++) {
                if (networks[j].connected)
                    return networks[j];
            }
        }
        return null;
    }

    standalone: true

    // The glyph alone says "wifi", never which network or how well. Same
    // precedence the glyph uses (wired beats wifi beats nothing). The
    // trailing segment states the M26 Task 9 right-click action —
    // otherwise it's undiscoverable.
    // ⚠️ signalStrength is a 0..1 fraction, not a percent (quickshell
    // src/network/wifi.hpp:23) — the same conversion NetworkPanel.qml's own
    // signal column makes.
    tooltipText: {
        var head;
        if (root._wiredConnected)
            head = "NETWORK / WIRED";
        else if (root._activeWifi)
            head = "WI-FI / " + root._activeWifi.name + " " + Math.round(root._activeWifi.signalStrength * 100) + "%";
        else if (root._wifiConnected)
            head = "WI-FI / CONNECTED";
        else
            head = "NETWORK / OFFLINE";
        return head + " / RIGHT " + (Networking.wifiEnabled ? "WI-FI OFF" : "WI-FI ON");
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: root._icon
        color: root.foreground
    }

    panelOpen: root._panelOpen

    interactive: true
    // M26 Task 9: right click toggles the Wi-Fi radio, middle also opens
    // the panel (upstream's redundant left/middle idiom, `manual/
    // 05-the-top-bar.md`'s Audio row).
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            Networking.wifiEnabled = !Networking.wifiEnabled;
        } else if (root.panel) {
            root.panel.toggleFrom(root);
        }
    }
}

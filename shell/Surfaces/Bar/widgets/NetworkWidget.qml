import QtQuick
import Quickshell.Networking
import qs.Core
import qs.Components

// Bar cell for network status (DESIGN.md §Bar's "network/BT glyphs" indicator
// slot, spec §1, M6 Task 6): a single glyph for the strongest active
// connection (wired beats wifi beats disconnected), click toggles the
// network panel anchored under this cell — same panel-open accent dot idiom
// as AudioWidget.qml/Clock.qml. Glyph codepoints taken from the pinned
// nerd-fonts-jetbrains-mono cmap (nix/testvm.nix), not memory: md-ethernet
// U+F0200, md-wifi U+F05A9, md-wifi_off U+F05AA.
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
    readonly property string _glyph: root._wiredConnected ? "󰈀" : (root._wifiConnected ? "󰖩" : "󰖪")

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
    hovered: hoverArea.containsMouse

    // The glyph alone says "wifi", never which network or how well. Same
    // precedence the glyph uses (wired beats wifi beats nothing).
    // ⚠️ signalStrength is a 0..1 fraction, not a percent (quickshell
    // src/network/wifi.hpp:23) — the same conversion NetworkPanel.qml's own
    // signal column makes.
    tooltipText: {
        if (root._wiredConnected)
            return "NETWORK / WIRED";
        if (root._activeWifi)
            return "WI-FI / " + root._activeWifi.name + " " + Math.round(root._activeWifi.signalStrength * 100) + "%";
        if (root._wifiConnected)
            return "WI-FI / CONNECTED";
        return "NETWORK / OFFLINE";
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

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.panel)
                root.panel.toggle(root.mapToItem(null, 0, 0).x);
        }
    }
}

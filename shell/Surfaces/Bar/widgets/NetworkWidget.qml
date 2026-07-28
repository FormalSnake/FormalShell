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

    hovered: hoverArea.containsMouse

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root._glyph
        color: root.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
    }

    Rectangle {
        visible: root._panelOpen
        width: 4
        height: 4
        radius: Theme.radius
        color: Theme.color.accent
        anchors.top: parent.top
        anchors.right: parent.right
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

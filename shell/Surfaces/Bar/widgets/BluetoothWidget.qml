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
    readonly property bool _connected: root._adapter
        ? root._adapter.devices.values.some(function (d) { return d.connected; })
        : false
    readonly property string _glyph: (!root._adapter || !root._adapter.enabled)
        ? "󰂲"
        : (root._connected ? "󰂱" : "󰂯")

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

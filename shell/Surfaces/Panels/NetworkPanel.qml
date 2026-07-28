import QtQuick
import Quickshell.Networking
import qs.Core
import qs.Components

// Network panel (DESIGN.md §Panels, spec §2, M6 Task 6): a ledger table of
// known connections grouped WIRED then WI-FI (mirroring AudioPanel's
// OUTPUT/INPUT split), each row a full-width cell, the active connection
// inverted, connect/disconnect as a row action mirroring AudioPanel's MUTE
// cell. Wifi rows additionally show signal strength as a mono bar — block/
// light-shade characters, not a flat Rectangle fill, since that fill idiom
// is reserved for continuous values (volume, year progress) while a signal
// reading is discrete. Bound directly to Quickshell.Networking, same as
// AudioPanel binds Pipewire directly rather than going through a Services
// wrapper. Honest empty state: "NO DEVICES" when Networking.devices is
// empty; a section with zero networks (the VM's no-Wi-Fi-radio case) simply
// omits its header rather than inventing a placeholder row.
Panel {
    id: root

    panelTitle: "NETWORK"

    function _signalBar(strength) {
        var segments = 5;
        var filled = Math.round(Math.max(0, Math.min(100, strength)) / 100 * segments);
        var bar = "";
        for (var i = 0; i < segments; i++)
            bar += (i < filled) ? "█" : "░";
        return bar;
    }

    readonly property var _entries: {
        var out = [];
        var devices = Networking.devices.values;
        for (var i = 0; i < devices.length; i++) {
            var device = devices[i];
            var networks = device.networks.values;
            for (var j = 0; j < networks.length; j++)
                out.push({ device: device, network: networks[j] });
        }
        return out;
    }
    readonly property var _wiredEntries: root._entries.filter(function (e) { return e.device.type === DeviceType.Wired; })
    readonly property var _wifiEntries: root._entries.filter(function (e) { return e.device.type === DeviceType.Wifi; })

    Component {
        id: networkRow

        Cell {
            id: netCell
            required property var modelData
            width: parent.width
            selected: netCell.modelData.network.connected

            Column {
                width: parent.width
                spacing: Theme.spacing.xs

                Row {
                    width: parent.width
                    spacing: Theme.spacing.sm

                    Text {
                        width: parent.width - actionCell.width - parent.spacing
                        text: netCell.modelData.network.name || "(unnamed)"
                        color: netCell.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.body
                        elide: Text.ElideRight
                    }

                    Cell {
                        id: actionCell
                        width: implicitWidth
                        height: implicitHeight
                        selected: netCell.modelData.network.connected

                        MetaLabel {
                            text: netCell.modelData.network.connected ? "DISCONNECT" : "CONNECT"
                            color: actionCell.foreground
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (netCell.modelData.network.connected)
                                    netCell.modelData.network.disconnect();
                                else
                                    netCell.modelData.network.connect();
                            }
                        }
                    }
                }

                Text {
                    visible: typeof netCell.modelData.network.signalStrength === "number"
                    text: root._signalBar(netCell.modelData.network.signalStrength) + "  " + Math.round(netCell.modelData.network.signalStrength) + "%"
                    color: netCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.caption
                }
            }
        }
    }

    Cell {
        visible: root._wiredEntries.length === 0 && root._wifiEntries.length === 0
        width: parent.width

        MetaLabel { text: "NO DEVICES" }
    }

    Cell {
        visible: root._wiredEntries.length > 0
        width: parent.width

        MetaLabel { text: "WIRED" }
    }

    Repeater {
        model: root._wiredEntries
        delegate: networkRow
    }

    Cell {
        visible: root._wifiEntries.length > 0
        width: parent.width

        MetaLabel { text: "WI-FI" }
    }

    Repeater {
        model: root._wifiEntries
        delegate: networkRow
    }
}

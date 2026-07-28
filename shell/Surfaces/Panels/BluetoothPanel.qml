import QtQuick
import Quickshell.Bluetooth
import qs.Core
import qs.Components

// Bluetooth panel (DESIGN.md §Panels, spec §2, M6 Task 6): adapter state
// cell (name + BluetoothAdapterState.toString + a POWER toggle mirroring
// AudioPanel's MUTE cell), then paired devices with connect/disconnect as a
// row action, the connected device inverted. Bound directly to
// Quickshell.Bluetooth, same as AudioPanel binds Pipewire directly. The test
// VM has no adapter at all — Bluetooth.defaultAdapter is then null and the
// panel renders a single dim "NO ADAPTER" cell, the honest-unavailable-state
// this plan requires rather than a fabricated device.
Panel {
    id: root

    panelTitle: "BLUETOOTH"

    readonly property var _adapter: Bluetooth.defaultAdapter
    readonly property var _pairedDevices: root._adapter
        ? root._adapter.devices.values.filter(function (d) { return d.paired; })
        : []

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
                text: root._adapter ? root._adapter.name + "  " + BluetoothAdapterState.toString(root._adapter.state) : ""
                color: adapterCell.foreground
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
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

    Cell {
        visible: root._adapter !== null && root._pairedDevices.length === 0
        width: parent.width

        MetaLabel { text: "NO DEVICES" }
    }

    Cell {
        visible: root._pairedDevices.length > 0
        width: parent.width

        MetaLabel { text: "PAIRED" }
    }

    Component {
        id: deviceRow

        Cell {
            id: deviceCell
            required property var modelData
            width: parent.width
            selected: deviceCell.modelData.connected

            Row {
                width: parent.width
                spacing: Theme.spacing.sm

                Text {
                    width: parent.width - connectCell.width - parent.spacing
                    text: deviceCell.modelData.name || deviceCell.modelData.deviceName
                    color: deviceCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.body
                    elide: Text.ElideRight
                }

                Cell {
                    id: connectCell
                    width: implicitWidth
                    height: implicitHeight
                    selected: deviceCell.modelData.connected

                    MetaLabel {
                        text: deviceCell.modelData.connected ? "DISCONNECT" : "CONNECT"
                        color: connectCell.foreground
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (deviceCell.modelData.connected)
                                deviceCell.modelData.disconnect();
                            else
                                deviceCell.modelData.connect();
                        }
                    }
                }
            }
        }
    }

    Repeater {
        model: root._pairedDevices
        delegate: deviceRow
    }
}

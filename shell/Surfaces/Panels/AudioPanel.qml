import QtQuick
import Quickshell.Services.Pipewire
import qs.Core
import qs.Components

// Per-node Pipewire volume sliders (DESIGN.md §Panels, spec §2, M6 Task 1):
// output nodes (hardware sinks) first, then inputs (hardware sources) — app
// streams excluded, this lists devices, not a full mixer. Bound via
// PwObjectTracker per AudioService.qml's own header note: PwNodeAudio's
// volume/muted are invalid until the node is bound.
Panel {
    id: root

    panelTitle: "AUDIO"

    readonly property var _audioNodes: Pipewire.nodes.values.filter(function (n) {
        return n.audio !== null && !n.isStream;
    })
    readonly property var _outputs: root._audioNodes.filter(function (n) { return n.isSink; })
    readonly property var _inputs: root._audioNodes.filter(function (n) { return !n.isSink; })

    PwObjectTracker {
        objects: root._audioNodes
    }

    Component {
        id: nodeRow

        Cell {
            id: nodeCell
            required property var modelData
            width: parent.width

            Column {
                width: parent.width
                spacing: Theme.spacing.xs

                Row {
                    width: parent.width
                    spacing: Theme.spacing.sm

                    Text {
                        width: parent.width - muteCell.width - parent.spacing
                        text: (nodeCell.modelData.description || nodeCell.modelData.name)
                            + "  " + Math.round(nodeCell.modelData.audio.volume * 100) + "%"
                        color: nodeCell.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.body
                        elide: Text.ElideRight
                    }

                    Cell {
                        id: muteCell
                        width: implicitWidth
                        height: implicitHeight
                        selected: nodeCell.modelData.audio.muted

                        MetaLabel {
                            text: "MUTE"
                            color: muteCell.foreground
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: nodeCell.modelData.audio.muted = !nodeCell.modelData.audio.muted
                        }
                    }
                }

                // Flat accent fill, no thumb, no radius — DESIGN.md's
                // "sliders are full-width cells whose fill level is a flat
                // accent block" rule. Click or drag along it to set volume.
                Rectangle {
                    id: fillTrack
                    width: parent.width
                    height: 6
                    color: Theme.color.rule

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, nodeCell.modelData.audio.volume))
                        height: parent.height
                        color: Theme.color.accent
                    }

                    MouseArea {
                        anchors.fill: parent
                        function _setFromX(x) {
                            nodeCell.modelData.audio.volume = Math.max(0, Math.min(1, x / fillTrack.width));
                        }
                        onPressed: mouse => _setFromX(mouse.x)
                        onPositionChanged: mouse => { if (pressed) _setFromX(mouse.x); }
                    }
                }
            }
        }
    }

    Cell {
        visible: root._outputs.length === 0 && root._inputs.length === 0
        width: parent.width

        MetaLabel { text: "NO DEVICES" }
    }

    Cell {
        visible: root._outputs.length > 0
        width: parent.width

        MetaLabel { text: "OUTPUT" }
    }

    Repeater {
        model: root._outputs
        delegate: nodeRow
    }

    Cell {
        visible: root._inputs.length > 0
        width: parent.width

        MetaLabel { text: "INPUT" }
    }

    Repeater {
        model: root._inputs
        delegate: nodeRow
    }
}

import QtQuick
import Quickshell.Services.Pipewire
import qs.Core
import qs.Components
import "../../Audio/model.js" as AudioModel

// Omarchy mixer behavior (DESIGN.md §Panels, spec §2, M6 Task 1; M15 Task 4):
// OUTPUT — one master slider row for the current default sink, then one
// selectable row per candidate sink (click/Enter sets
// Pipewire.preferredDefaultAudioSink, the active row inverted); INPUT is
// the same shape for sources, the whole section (header included) omitted
// when no input hardware exists; APPS lists real playback streams
// (Audio/model.js.isPlaybackStream, never reading `properties` at filter
// time — the omarchy destabilization note), omitted entirely with no
// streams. Master sliders clamp 0..1 (AudioModel.clampDevice); stream
// tracks allow 0..1.5 overdrive (AudioModel.clampStream) with a hairline
// notch at the 1.0 mark so overdrive reads as deliberate, not a broken
// track. Keyboard: Up/Down walk one combined cursor across every row
// (master sliders count as their own row), h/l adjust 5% on whatever
// slider-shaped row the cursor sits on, m mutes it, Enter activates
// (default-switch on a device row, mute-toggle everywhere else) — the same
// `Panel.keyPressed` hook NetworkPanel/PowerPanel already consume. Wheel
// over any track steps 5% too. PwNode.audio's volume/muted (and
// .properties, read only once .ready — the stream label's fallback chain)
// are invalid until bound, so every node this panel touches, streams
// included, goes through the shared PwObjectTracker below.
Panel {
    id: root

    panelTitle: "AUDIO"
    panelWidth: Theme.space.popupWidthDefault

    readonly property var _sink: Pipewire.defaultAudioSink
    readonly property var _source: Pipewire.defaultAudioSource

    readonly property var _deviceNodes: Pipewire.nodes.values.filter(function (n) {
        return n.audio !== null && !n.isStream;
    })
    readonly property var _outputs: root._deviceNodes.filter(function (n) { return n.isSink; })
    readonly property var _inputs: root._deviceNodes.filter(function (n) { return !n.isSink; })

    readonly property var _streams: Pipewire.nodes.values.filter(function (n) {
        return n.audio !== null && AudioModel.isPlaybackStream(n);
    })

    readonly property var _outputRows: root._outputs.map(function (n) {
        return { node: n, cursorKey: "output-device:" + n.id, isOutput: true };
    })
    readonly property var _inputRows: root._inputs.map(function (n) {
        return { node: n, cursorKey: "input-device:" + n.id, isOutput: false };
    })
    readonly property var _streamRows: root._streams.map(function (n) {
        return { node: n, cursorKey: "stream:" + n.id };
    })

    PwObjectTracker {
        objects: root._deviceNodes.concat(root._streams)
    }

    // One flat cursor across master sliders (role "slider", section
    // "output"/"input"), device rows (role "device"), and stream rows
    // (role "slider", section "stream") — mirrors NetworkPanel's
    // string-identity cursor (`_cursorSsid`) rather than PowerPanel's
    // single-list numeric one, since this panel spans several Repeaters.
    property string _cursorKey: ""

    readonly property var _cursorEntries: {
        var out = [];
        if (root._sink && root._sink.audio)
            out.push({ key: "output-slider", section: "output", role: "slider" });
        for (var i = 0; i < root._outputRows.length; i++)
            out.push({ key: root._outputRows[i].cursorKey, section: "output", role: "device", node: root._outputRows[i].node });
        if (root._inputs.length > 0) {
            if (root._source && root._source.audio)
                out.push({ key: "input-slider", section: "input", role: "slider" });
            for (var j = 0; j < root._inputRows.length; j++)
                out.push({ key: root._inputRows[j].cursorKey, section: "input", role: "device", node: root._inputRows[j].node });
        }
        for (var k = 0; k < root._streamRows.length; k++)
            out.push({ key: root._streamRows[k].cursorKey, section: "stream", role: "slider", node: root._streamRows[k].node });
        return out;
    }

    function _cursorIndex() {
        for (var i = 0; i < root._cursorEntries.length; i++)
            if (root._cursorEntries[i].key === root._cursorKey)
                return i;
        return -1;
    }

    function _cursorEntry() {
        var idx = root._cursorIndex();
        return idx >= 0 ? root._cursorEntries[idx] : null;
    }

    function _moveCursor(delta) {
        var entries = root._cursorEntries;
        if (entries.length === 0) {
            root._cursorKey = "";
            return;
        }
        var idx = root._cursorIndex();
        if (idx < 0)
            idx = delta > 0 ? 0 : entries.length - 1;
        else
            idx = Math.max(0, Math.min(entries.length - 1, idx + delta));
        root._cursorKey = entries[idx].key;
    }

    function _adjustCursorVolume(delta) {
        var entry = root._cursorEntry();
        if (!entry || entry.role !== "slider")
            return;
        if (entry.section === "output" && root._sink && root._sink.audio)
            root._sink.audio.volume = AudioModel.clampDevice(root._sink.audio.volume + delta);
        else if (entry.section === "input" && root._source && root._source.audio)
            root._source.audio.volume = AudioModel.clampDevice(root._source.audio.volume + delta);
        else if (entry.section === "stream" && entry.node && entry.node.audio)
            entry.node.audio.volume = AudioModel.clampStream(entry.node.audio.volume + delta);
    }

    function _muteCursor() {
        var entry = root._cursorEntry();
        if (!entry)
            return;
        if (entry.section === "output" && root._sink && root._sink.audio)
            root._sink.audio.muted = !root._sink.audio.muted;
        else if (entry.section === "input" && root._source && root._source.audio)
            root._source.audio.muted = !root._source.audio.muted;
        else if (entry.section === "stream" && entry.node && entry.node.audio)
            entry.node.audio.muted = !entry.node.audio.muted;
    }

    function _activateCursor() {
        var entry = root._cursorEntry();
        if (!entry)
            return;
        if (entry.role === "device") {
            if (entry.section === "output")
                Pipewire.preferredDefaultAudioSink = entry.node;
            else
                Pipewire.preferredDefaultAudioSource = entry.node;
            return;
        }
        root._muteCursor();
    }

    onIsOpenChanged: if (!root.isOpen) root._cursorKey = ""

    // Panel.qml's shared keyboard-nav hook (M6 Task 7, PowerPanel/
    // NetworkPanel's consumer pattern): Up/Down move the cursor, h/l step
    // whatever slider it's on by 5%, m mutes, Enter activates.
    Connections {
        target: root

        function onKeyPressed(event) {
            if (!root.isOpen)
                return;
            if (event.key === Qt.Key_Up) {
                root._moveCursor(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Down) {
                root._moveCursor(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root._activateCursor();
                event.accepted = true;
            } else if (event.text === "h" || event.text === "H") {
                root._adjustCursorVolume(-0.05);
                event.accepted = true;
            } else if (event.text === "l" || event.text === "L") {
                root._adjustCursorVolume(0.05);
                event.accepted = true;
            } else if (event.text === "m" || event.text === "M") {
                root._muteCursor();
                event.accepted = true;
            }
        }
    }

    Component {
        id: deviceRow

        Cell {
            id: deviceCell
            required property var modelData
            width: parent.width
            selected: deviceCell.modelData.isOutput
                ? (root._sink !== null && deviceCell.modelData.node.id === root._sink.id)
                : (root._source !== null && deviceCell.modelData.node.id === root._source.id)
            hovered: root._cursorKey === deviceCell.modelData.cursorKey

            Text {
                width: parent.width
                text: deviceCell.modelData.node.description || deviceCell.modelData.node.name
                color: deviceCell.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
                elide: Text.ElideRight
            }

            interactive: true
            onClicked: {
                if (deviceCell.modelData.isOutput)
                    Pipewire.preferredDefaultAudioSink = deviceCell.modelData.node;
                else
                    Pipewire.preferredDefaultAudioSource = deviceCell.modelData.node;
            }
        }
    }

    Component {
        id: streamRow

        Cell {
            id: streamCell
            required property var modelData
            width: parent.width
            hovered: root._cursorKey === streamCell.modelData.cursorKey

            readonly property var _node: streamCell.modelData.node
            readonly property var _audio: streamCell._node ? streamCell._node.audio : null
            readonly property real _volume: streamCell._audio ? streamCell._audio.volume : 0
            readonly property bool _muted: streamCell._audio ? streamCell._audio.muted : false
            readonly property var _props: streamCell._node && streamCell._node.ready ? streamCell._node.properties : ({})
            readonly property string _label: AudioModel.streamLabel(streamCell._props,
                streamCell._node ? streamCell._node.description : "",
                streamCell._node ? streamCell._node.name : "") || "Stream"

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                Row {
                    width: parent.width
                    spacing: Theme.space.sm

                    Text {
                        width: parent.width - streamPercent.width - streamMuteCell.width - parent.spacing * 2
                        text: streamCell._label
                        color: streamCell.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.body
                        elide: Text.ElideRight
                    }

                    Text {
                        id: streamPercent
                        text: Math.round(streamCell._volume * 100) + "%"
                        color: streamCell._muted ? Theme.color.foregroundFaint : streamCell.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.caption
                    }

                    Cell {
                        id: streamMuteCell
                        width: implicitWidth
                        height: implicitHeight
                        selected: streamCell._muted

                        MetaLabel { text: "MUTE"; color: streamMuteCell.foreground }

                        interactive: true
                        onClicked: if (streamCell._audio) streamCell._audio.muted = !streamCell._audio.muted
                    }
                }

                DitherFill {
                    id: streamTrack
                    width: parent.width
                    height: Theme.space.trackThickness

                    Rectangle {
                        width: parent.width * Math.min(1, streamCell._volume / 1.5)
                        height: parent.height
                        color: Theme.color.accent
                    }

                    // The 1.0 boundary, at 2/3 of the 0..1.5 track — cuts a
                    // notch through fill and empty track alike so crossing
                    // into overdrive reads as a deliberate line, not the
                    // track simply running out of room. Deliberately 1px, not
                    // `Theme.borderWidth`: this isn't a border or a rule
                    // (§1.4's ink hierarchy doesn't apply), it's a
                    // background-colored cut through a fill — the 2/0 border
                    // convention (audit "border widths") doesn't govern it.
                    Rectangle {
                        x: parent.width * (1 / 1.5) - width / 2
                        width: 1
                        height: parent.height
                        color: Theme.color.background
                    }

                    MouseArea {
                        anchors.fill: parent
                        function _setFromX(x) {
                            if (!streamCell._audio) return;
                            streamCell._audio.volume = AudioModel.clampStream((x / streamTrack.width) * 1.5);
                        }
                        onPressed: mouse => _setFromX(mouse.x)
                        onPositionChanged: mouse => { if (pressed) _setFromX(mouse.x); }
                        onWheel: wheel => {
                            if (!streamCell._audio) return;
                            streamCell._audio.volume = AudioModel.clampStream(streamCell._volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05));
                            wheel.accepted = true;
                        }
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

        MetaLabel { text: "OUTPUT"; colon: true }
    }

    Cell {
        id: outputMasterCell
        visible: root._sink !== null && root._sink.audio !== null
        hovered: root._cursorKey === "output-slider"
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.space.xxs

            Row {
                width: parent.width
                spacing: Theme.space.sm

                Text {
                    width: parent.width - outputMuteCell.width - parent.spacing
                    text: Math.round((root._sink && root._sink.audio ? root._sink.audio.volume : 0) * 100) + "%"
                    color: outputMasterCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }

                Cell {
                    id: outputMuteCell
                    width: implicitWidth
                    height: implicitHeight
                    selected: root._sink && root._sink.audio && root._sink.audio.muted

                    MetaLabel { text: "MUTE"; color: outputMuteCell.foreground }

                    interactive: true
                    onClicked: if (root._sink && root._sink.audio) root._sink.audio.muted = !root._sink.audio.muted
                }
            }

            DitherFill {
                id: outputTrack
                width: parent.width
                height: Theme.space.trackThickness

                Rectangle {
                    width: parent.width * (root._sink && root._sink.audio ? AudioModel.clampDevice(root._sink.audio.volume) : 0)
                    height: parent.height
                    color: Theme.color.accent
                }

                MouseArea {
                    anchors.fill: parent
                    function _setFromX(x) {
                        if (!root._sink || !root._sink.audio) return;
                        root._sink.audio.volume = AudioModel.clampDevice(x / outputTrack.width);
                    }
                    onPressed: mouse => _setFromX(mouse.x)
                    onPositionChanged: mouse => { if (pressed) _setFromX(mouse.x); }
                    onWheel: wheel => {
                        if (!root._sink || !root._sink.audio) return;
                        root._sink.audio.volume = AudioModel.clampDevice(root._sink.audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05));
                        wheel.accepted = true;
                    }
                }
            }
        }
    }

    Repeater {
        model: root._outputRows
        delegate: deviceRow
    }

    Cell {
        visible: root._inputs.length > 0
        width: parent.width

        MetaLabel { text: "INPUT"; colon: true }
    }

    Cell {
        id: inputMasterCell
        visible: root._inputs.length > 0 && root._source !== null && root._source.audio !== null
        hovered: root._cursorKey === "input-slider"
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.space.xxs

            Row {
                width: parent.width
                spacing: Theme.space.sm

                Text {
                    width: parent.width - inputMuteCell.width - parent.spacing
                    text: Math.round((root._source && root._source.audio ? root._source.audio.volume : 0) * 100) + "%"
                    color: inputMasterCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }

                Cell {
                    id: inputMuteCell
                    width: implicitWidth
                    height: implicitHeight
                    selected: root._source && root._source.audio && root._source.audio.muted

                    MetaLabel { text: "MUTE"; color: inputMuteCell.foreground }

                    interactive: true
                    onClicked: if (root._source && root._source.audio) root._source.audio.muted = !root._source.audio.muted
                }
            }

            DitherFill {
                id: inputTrack
                width: parent.width
                height: Theme.space.trackThickness

                Rectangle {
                    width: parent.width * (root._source && root._source.audio ? AudioModel.clampDevice(root._source.audio.volume) : 0)
                    height: parent.height
                    color: Theme.color.accent
                }

                MouseArea {
                    anchors.fill: parent
                    function _setFromX(x) {
                        if (!root._source || !root._source.audio) return;
                        root._source.audio.volume = AudioModel.clampDevice(x / inputTrack.width);
                    }
                    onPressed: mouse => _setFromX(mouse.x)
                    onPositionChanged: mouse => { if (pressed) _setFromX(mouse.x); }
                    onWheel: wheel => {
                        if (!root._source || !root._source.audio) return;
                        root._source.audio.volume = AudioModel.clampDevice(root._source.audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05));
                        wheel.accepted = true;
                    }
                }
            }
        }
    }

    Repeater {
        model: root._inputRows
        delegate: deviceRow
    }

    Cell {
        visible: root._streams.length > 0
        width: parent.width

        MetaLabel { text: "APPS"; colon: true }
    }

    Repeater {
        model: root._streamRows
        delegate: streamRow
    }
}

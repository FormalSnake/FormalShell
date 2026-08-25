import QtQuick
import Quickshell.Services.Pipewire
import qs.Core
import qs.Components
import "../../Audio/model.js" as AudioModel

// Audio panel (DESIGN.md §3 "Panel", spec "Panels"): a hero card for the
// default sink (its name, mute state, volume percent and an interactive
// rail), `OUTPUT (n)` listing the other candidate sinks, an INPUT master
// row over the default source's own track with `INPUT (n)` under it, and
// `APPS (n)` for the live playback streams.
//
// The active sink is deliberately absent from the OUTPUT list: the hero
// already names it, and a row repeating that name would say it twice. The
// input list does carry its own default, marked `selected`.
//
// Keyboard (spec "Keyboard model"): one flat cursor walks every row, the
// two master sliders included; Left/Right steps whatever slider it sits on
// by 5%, `m` mutes it, Enter switches the default on a device row and
// mutes on a slider row. Wheel over any track steps 5% too. The cursor is
// keyed by row identity rather than by index, since a device appearing or
// a stream ending renumbers the list under it.
//
// Master sliders clamp 0..1 (AudioModel.clampDevice); stream tracks allow
// 0..1.5 overdrive (AudioModel.clampStream) with a notch at the 1.0 mark
// so overdrive reads as deliberate rather than as a track that ran out of
// room.
//
// PwNode.audio's volume/muted (and .properties, read only once .ready, the
// stream label's own fallback chain) are invalid until bound, so every
// node this panel touches, streams included, goes through the shared
// PwObjectTracker below.
Panel {
    id: root

    panelIcon: "volume-2"
    panelTitle: "Audio"
    panelWidth: Theme.space.popupWidthDefault

    readonly property var _sink: Pipewire.defaultAudioSink
    readonly property var _source: Pipewire.defaultAudioSource

    readonly property bool _outputMuted: root._sink !== null && root._sink.audio !== null && root._sink.audio.muted
    readonly property real _outputVolume: root._sink !== null && root._sink.audio !== null
        ? AudioModel.clampDevice(root._sink.audio.volume) : 0
    readonly property bool _inputMuted: root._source !== null && root._source.audio !== null && root._source.audio.muted
    readonly property real _inputVolume: root._source !== null && root._source.audio !== null
        ? AudioModel.clampDevice(root._source.audio.volume) : 0

    readonly property var _deviceNodes: Pipewire.nodes.values.filter(function (n) {
        return n.audio !== null && !n.isStream;
    })
    readonly property var _outputs: root._deviceNodes.filter(function (n) { return n.isSink; })
    readonly property var _inputs: root._deviceNodes.filter(function (n) { return !n.isSink; })

    readonly property var _streams: Pipewire.nodes.values.filter(function (n) {
        return n.audio !== null && AudioModel.isPlaybackStream(n);
    })

    readonly property var _outputRows: root._outputs.filter(function (n) {
        return root._sink === null || n.id !== root._sink.id;
    }).map(function (n) {
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
    // "output"/"input"), device rows (role "device") and stream rows (role
    // "slider", section "stream"), in the order the panel renders them.
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

    // The cursor's row identity, kept alongside Panel's own numeric
    // cursorIndex: the row list rebuilds whenever a device or a stream
    // comes and goes, and an index on its own would walk the cursor onto
    // whatever row slid underneath it.
    property string _cursorKey: ""

    function _entryAt(index) {
        return (index >= 0 && index < root._cursorEntries.length) ? root._cursorEntries[index] : null;
    }

    function _keyAt(index) {
        var entry = root._entryAt(index);
        return entry ? entry.key : "";
    }

    function _indexForKey(key) {
        for (var i = 0; i < root._cursorEntries.length; i++)
            if (root._cursorEntries[i].key === key)
                return i;
        return -1;
    }

    function _pointAt(key) {
        var index = root._indexForKey(key);
        if (index < 0)
            return;
        root.cursorActive = true;
        root.cursorIndex = index;
    }

    function _adjustVolume(entry, delta) {
        if (!entry || entry.role !== "slider")
            return;
        if (entry.section === "output" && root._sink && root._sink.audio)
            root._sink.audio.volume = AudioModel.clampDevice(root._sink.audio.volume + delta);
        else if (entry.section === "input" && root._source && root._source.audio)
            root._source.audio.volume = AudioModel.clampDevice(root._source.audio.volume + delta);
        else if (entry.section === "stream" && entry.node && entry.node.audio)
            entry.node.audio.volume = AudioModel.clampStream(entry.node.audio.volume + delta);
    }

    function _mute(entry) {
        if (!entry)
            return;
        if (entry.section === "output" && root._sink && root._sink.audio)
            root._sink.audio.muted = !root._sink.audio.muted;
        else if (entry.section === "input" && root._source && root._source.audio)
            root._source.audio.muted = !root._source.audio.muted;
        else if (entry.section === "stream" && entry.node && entry.node.audio)
            entry.node.audio.muted = !entry.node.audio.muted;
    }

    function _makeDefault(row) {
        if (!row)
            return;
        if (row.isOutput)
            Pipewire.preferredDefaultAudioSink = row.node;
        else
            Pipewire.preferredDefaultAudioSource = row.node;
    }

    cursorCount: root._cursorEntries.length
    // Left/Right belongs to the slider under the cursor, not to the list.
    cursorStepsHorizontally: true

    onCursorIndexChanged: root._cursorKey = root._keyAt(root.cursorIndex)

    on_CursorEntriesChanged: {
        var index = root._indexForKey(root._cursorKey);
        if (index >= 0 && index !== root.cursorIndex)
            root.cursorIndex = index;
    }

    onCursorActivated: index => {
        var entry = root._entryAt(index);
        if (!entry)
            return;
        if (entry.role === "device")
            root._makeDefault({ node: entry.node, isOutput: entry.section === "output" });
        else
            root._mute(entry);
    }

    onCursorStepped: (index, direction) => root._adjustVolume(root._entryAt(index), direction * 0.05)

    onCursorTextKey: text => {
        if (text === "m" || text === "M")
            root._mute(root._entryAt(root.cursorIndex));
    }

    // The cursor starts on the first row every open (devices can come and
    // go while the panel is closed), so the reveal-only first keypress has
    // a real position to show.
    onIsOpenChanged: {
        if (root.isOpen) {
            root.cursorIndex = 0;
            root.cursorSection = 0;
            root._cursorKey = root._keyAt(0);
        } else {
            root._cursorKey = "";
        }
    }

    Component {
        id: deviceRow

        Cell {
            id: deviceCell
            required property var modelData
            width: parent.width
            interactive: true
            selected: deviceCell.modelData.isOutput
                ? (root._sink !== null && deviceCell.modelData.node.id === root._sink.id)
                : (root._source !== null && deviceCell.modelData.node.id === root._source.id)
            cursor: root.cursorActive && root._cursorKey === deviceCell.modelData.cursorKey

            // A pointer reaching a row reveals the cursor on it, the same
            // gate the first navigation key flips.
            onContainsPointerChanged: if (deviceCell.containsPointer) root._pointAt(deviceCell.modelData.cursorKey)

            onClicked: root._makeDefault(deviceCell.modelData)

            Item {
                width: parent.width
                height: deviceName.implicitHeight

                Icon {
                    id: deviceIcon
                    name: deviceCell.modelData.isOutput ? "volume-2" : "mic"
                    size: Theme.fontSize.body
                    color: deviceCell.foreground
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    id: deviceName
                    anchors.left: deviceIcon.right
                    anchors.leftMargin: Theme.space.iconGap
                    anchors.right: deviceCheck.left
                    anchors.rightMargin: Theme.space.iconGap
                    anchors.verticalCenter: parent.verticalCenter
                    text: deviceCell.modelData.node.description || deviceCell.modelData.node.name
                    color: deviceCell.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                    elide: Text.ElideRight
                }

                Icon {
                    id: deviceCheck
                    name: "check"
                    size: Theme.fontSize.body
                    visible: deviceCell.selected
                    color: Theme.color.primary
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Component {
        id: streamRow

        Cell {
            id: streamCell
            required property var modelData
            width: parent.width
            interactive: true
            cursor: root.cursorActive && root._cursorKey === streamCell.modelData.cursorKey

            readonly property var _node: streamCell.modelData.node
            readonly property var _audio: streamCell._node ? streamCell._node.audio : null
            readonly property real _volume: streamCell._audio ? streamCell._audio.volume : 0
            readonly property bool _muted: streamCell._audio ? streamCell._audio.muted : false
            readonly property var _props: streamCell._node && streamCell._node.ready ? streamCell._node.properties : ({})
            readonly property string _label: AudioModel.streamLabel(streamCell._props,
                streamCell._node ? streamCell._node.description : "",
                streamCell._node ? streamCell._node.name : "") || "Stream"

            onContainsPointerChanged: if (streamCell.containsPointer) root._pointAt(streamCell.modelData.cursorKey)

            Column {
                width: parent.width
                spacing: Theme.space.xs

                Item {
                    width: parent.width
                    height: Math.max(streamLabelText.implicitHeight, streamValueRow.implicitHeight)

                    Text {
                        id: streamLabelText
                        anchors.left: parent.left
                        anchors.right: streamValueRow.left
                        anchors.rightMargin: Theme.space.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        text: streamCell._label
                        color: streamCell.foreground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                        elide: Text.ElideRight
                    }

                    Row {
                        id: streamValueRow
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space.iconGap

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(streamCell._volume * 100) + "%"
                            color: streamCell._muted ? Theme.color.mutedForeground : streamCell.dimForeground
                            font.family: Theme.fontFamilyMono
                            font.pixelSize: Theme.fontSize.bodySmall
                        }

                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            name: streamCell._muted ? "volume-x" : "volume-2"
                            onClicked: if (streamCell._audio) streamCell._audio.muted = !streamCell._audio.muted
                        }
                    }
                }

                Track {
                    id: streamTrack
                    width: parent.width
                    value: streamCell._volume / 1.5

                    // The 1.0 boundary, at 2/3 of the 0..1.5 track: a cut
                    // through fill and groove alike, so crossing into
                    // overdrive reads as a deliberate line.
                    Rectangle {
                        x: parent.width * (1 / 1.5) - width / 2
                        width: Theme.borderWidth
                        height: parent.height
                        color: Theme.color.background
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
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

    // The panel's own subject: the default sink, with its rail as the
    // master slider (press, drag and wheel) and mute in the trailing slot.
    PanelHero {
        id: outputHero
        visible: root._sink !== null && root._sink.audio !== null
        width: parent.width
        title: root._sink ? (root._sink.description || root._sink.name) : ""
        meta: root._outputMuted ? "Muted" : "Active"
        readout: Math.round(root._outputVolume * 100) + "%"
        rail: root._outputVolume
        railInteractive: true
        cursor: root.cursorActive && root._cursorKey === "output-slider"
        onRailPressed: fraction => { if (root._sink && root._sink.audio) root._sink.audio.volume = AudioModel.clampDevice(fraction); }
        onRailStepped: direction => { if (root._sink && root._sink.audio) root._sink.audio.volume = AudioModel.clampDevice(root._sink.audio.volume + direction * 0.05); }

        leading: Component {
            Icon {
                name: root._outputMuted ? "volume-x" : "volume-2"
                size: Theme.fontSize.heading
                color: outputHero.foreground
            }
        }

        trailing: Component {
            IconButton {
                name: root._outputMuted ? "volume-x" : "volume-2"
                onClicked: if (root._sink && root._sink.audio) root._sink.audio.muted = !root._sink.audio.muted
            }
        }
    }

    Cell {
        visible: root._outputs.length === 0 && root._inputs.length === 0
        width: parent.width

        SectionLabel { text: "NO DEVICES" }
    }

    Column {
        width: parent.width
        visible: root._outputRows.length > 0
        spacing: Theme.space.rowGap

        SectionLabel { text: "OUTPUT"; count: root._outputRows.length }

        Repeater {
            model: root._outputRows
            delegate: deviceRow
        }
    }

    Column {
        width: parent.width
        visible: root._inputs.length > 0
        spacing: Theme.space.rowGap

        // The default source's own master row: one line of label, percent
        // and mute, its track underneath, the same rhythm as a stream row.
        Cell {
            id: inputMasterCell
            width: parent.width
            interactive: true
            cursor: root.cursorActive && root._cursorKey === "input-slider"
            onContainsPointerChanged: if (inputMasterCell.containsPointer) root._pointAt("input-slider")

            Column {
                width: parent.width
                spacing: Theme.space.xs

                Item {
                    width: parent.width
                    height: Math.max(inputLabel.implicitHeight, inputValueRow.implicitHeight)

                    Icon {
                        id: inputIcon
                        name: root._inputMuted ? "mic-off" : "mic"
                        size: Theme.fontSize.body
                        color: inputMasterCell.foreground
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        id: inputLabel
                        anchors.left: inputIcon.right
                        anchors.leftMargin: Theme.space.iconGap
                        anchors.right: inputValueRow.left
                        anchors.rightMargin: Theme.space.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Input"
                        color: inputMasterCell.foreground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                        elide: Text.ElideRight
                    }

                    Row {
                        id: inputValueRow
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space.iconGap

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(root._inputVolume * 100) + "%"
                            color: root._inputMuted ? Theme.color.mutedForeground : inputMasterCell.dimForeground
                            font.family: Theme.fontFamilyMono
                            font.pixelSize: Theme.fontSize.bodySmall
                        }

                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            name: root._inputMuted ? "mic-off" : "mic"
                            onClicked: if (root._source && root._source.audio) root._source.audio.muted = !root._source.audio.muted
                        }
                    }
                }

                Track {
                    id: inputTrack
                    width: parent.width
                    value: root._inputVolume

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
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

        SectionLabel { text: "INPUT"; count: root._inputRows.length }

        Repeater {
            model: root._inputRows
            delegate: deviceRow
        }
    }

    Column {
        width: parent.width
        visible: root._streamRows.length > 0
        spacing: Theme.space.rowGap

        SectionLabel { text: "APPS"; count: root._streamRows.length }

        Repeater {
            model: root._streamRows
            delegate: streamRow
        }
    }
}

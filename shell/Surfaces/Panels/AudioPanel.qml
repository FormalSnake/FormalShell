import QtQuick
import Quickshell.Services.Pipewire
import qs.Core
import qs.Components
import "../../Audio/model.js" as AudioModel

// Audio panel (DESIGN.md §3 "Panel", spec "Panels"): a hero card for the
// default sink (its name, mute state, volume percent, an interactive rail
// and an audible/muted `Switch`), `OUTPUT (n)` listing the other candidate
// sinks, an INPUT master row over the default source's own track with
// `INPUT (n)` under it, and `APPS (n)` for the live playback streams. Every
// mute on this panel is a `Switch` whose checked state is "audible": the row
// beside it already names what is being muted.
//
// The active sink is deliberately absent from the OUTPUT list: the hero
// already names it, and a row repeating that name would say it twice. The
// input list does carry its own default, marked `selected`. Two or three
// candidates render as a `ButtonGroup` pick instead of a list (M48 D1), and
// that form does carry the active device, since it is the control saying
// which one is chosen.
//
// Keyboard (spec "Keyboard model"): one flat cursor walks every row, the
// two master sliders included; Left/Right steps whatever slider it sits on
// by 5% and walks the buttons of a device pick, `m` mutes it, Enter switches
// the default on a device row or pick and mutes on a slider row. Wheel over
// any track steps 5% too. The cursor is keyed by row identity rather than by
// index, since a device appearing or a stream ending renumbers the list
// under it.
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

    // Both node lists read the Pipewire model only while the panel is open:
    // a closed panel would otherwise re-filter, re-map and re-bind every
    // node on each graph change, and a node-churning client (Easy Effects'
    // meters come and go dozens of times a second) turns that into a
    // standing cost. AudioService keeps the default sink and source bound
    // on its own, so nothing the bar shows depends on these.
    readonly property var _deviceNodes: root.isOpen ? Pipewire.nodes.values.filter(function (n) {
        return n.audio !== null && !n.isStream;
    }) : []
    readonly property var _outputs: root._deviceNodes.filter(function (n) { return n.isSink; })
    readonly property var _inputs: root._deviceNodes.filter(function (n) { return !n.isSink; })

    readonly property var _streams: root.isOpen ? Pipewire.nodes.values.filter(function (n) {
        return n.audio !== null && AudioModel.isPlaybackStream(n);
    }) : []

    // Two or three candidates read better as one pick than as a list of
    // rows (M48 D1, omarchy's own shape): the section becomes a
    // `ButtonGroup` and the list is empty. Four or more stay a list, where a
    // trough would leave each label a sliver.
    function _isGroupCount(n) {
        return n >= 2 && n <= 3;
    }

    readonly property bool _outputPick: root._isGroupCount(root._outputs.length)
    readonly property bool _inputPick: root._isGroupCount(root._inputs.length)

    // The pick carries every output, the active one included: it is the
    // control that says which sink is chosen, so the chosen one has to be in
    // it. The list form leaves the active sink out, since the hero above
    // already names it.
    readonly property var _outputRows: (root._outputPick ? [] : root._outputs.filter(function (n) {
        return root._sink === null || n.id !== root._sink.id;
    })).map(function (n) {
        return { node: n, cursorKey: "output-device:" + n.id, isOutput: true };
    })
    readonly property var _inputRows: (root._inputPick ? [] : root._inputs).map(function (n) {
        return { node: n, cursorKey: "input-device:" + n.id, isOutput: false };
    })

    function _deviceLabel(node) {
        return node.description || node.name;
    }

    readonly property var _outputOptions: root._outputs.map(function (n) {
        return { icon: "volume-2", label: root._deviceLabel(n), value: n.id };
    })
    readonly property var _inputOptions: root._inputs.map(function (n) {
        return { icon: "mic", label: root._deviceLabel(n), value: n.id };
    })

    function _indexOfNode(nodes, node) {
        if (!node)
            return 0;
        for (var i = 0; i < nodes.length; i++)
            if (nodes[i].id === node.id)
                return i;
        return 0;
    }

    readonly property int _outputSelected: root._indexOfNode(root._outputs, root._sink)
    readonly property int _inputSelected: root._indexOfNode(root._inputs, root._source)
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
        if (root._outputPick)
            out.push({ key: "output-pick", section: "output", role: "pick" });
        for (var i = 0; i < root._outputRows.length; i++)
            out.push({ key: root._outputRows[i].cursorKey, section: "output", role: "device", node: root._outputRows[i].node });
        if (root._inputs.length > 0) {
            if (root._source && root._source.audio)
                out.push({ key: "input-slider", section: "input", role: "slider" });
            if (root._inputPick)
                out.push({ key: "input-pick", section: "input", role: "pick" });
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

    // A `pick` entry is one cursor stop holding the whole device group, so
    // Enter presses the button under its own ring and Left/Right walk that
    // group instead of stepping a volume.
    function _groupFor(entry) {
        if (!entry || entry.role !== "pick")
            return null;
        return entry.section === "output" ? outputPickGroup : inputPickGroup;
    }

    onCursorActivated: index => {
        var entry = root._entryAt(index);
        if (!entry)
            return;
        var group = root._groupFor(entry);
        if (group)
            group.activate();
        else if (entry.role === "device")
            root._makeDefault({ node: entry.node, isOutput: entry.section === "output" });
        else
            root._mute(entry);
    }

    onCursorStepped: (index, direction) => {
        var entry = root._entryAt(index);
        var group = root._groupFor(entry);
        if (group)
            group.step(direction);
        else
            root._adjustVolume(entry, direction * 0.05);
    }

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
            ghost: true
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
            ghost: true
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

                        // Sound on or off is a state, so it is a `Switch`
                        // (DESIGN.md §2). Checked is "audible": the row's
                        // own label says which stream, and the percentage
                        // beside it says how loud.
                        Switch {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: !streamCell._muted
                            onToggled: checked => { if (streamCell._audio) streamCell._audio.muted = !checked; }
                        }
                    }
                }

                Track {
                    id: streamTrack
                    width: parent.width
                    value: streamCell._volume / 1.5
                    // The 1.0 boundary, at 2/3 of the 0..1.5 track.
                    notch: 1 / 1.5

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
            Switch {
                checked: !root._outputMuted
                onToggled: checked => { if (root._sink && root._sink.audio) root._sink.audio.muted = !checked; }
            }
        }
    }

    SectionLabel {
        visible: root._outputs.length === 0 && root._inputs.length === 0
        leftPadding: Theme.space.controlPaddingX
        text: "NO DEVICES"
    }

    Column {
        width: parent.width
        visible: root._outputPick || root._outputRows.length > 0
        spacing: Theme.space.rowGap

        SectionLabel {
            leftPadding: Theme.space.controlPaddingX
            text: "OUTPUT"
            count: root._outputPick ? root._outputs.length : root._outputRows.length
        }

        ButtonGroup {
            id: outputPickGroup
            visible: root._outputPick
            width: parent.width
            options: root._outputOptions
            index: root._outputSelected
            cursor: root.cursorActive && root._cursorKey === "output-pick"
            onChanged: index => root._makeDefault({ node: root._outputs[index], isOutput: true })
            onHovered: (index, isHovered) => {
                if (!isHovered)
                    return;
                root._pointAt("output-pick");
                outputPickGroup.cursorIndex = index;
            }
        }

        // A borderless row leaves no box for a gap to sit between, so the rows
        // in a section abut and only `sectionGap` separates the sections.
        Column {
            width: parent.width
            spacing: 0

            Repeater {
                model: root._outputRows
                delegate: deviceRow
            }
        }
    }

    // The default source's own master row: one line of label, percent
    // and mute, its track underneath, the same rhythm as a stream row.
    // It opens the input the way the hero opens the output, so it sits a
    // section away from the list below rather than inside it.
    Cell {
        id: inputMasterCell
        visible: root._inputs.length > 0
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

                    Switch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: !root._inputMuted
                        onToggled: checked => { if (root._source && root._source.audio) root._source.audio.muted = !checked; }
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

    Column {
        width: parent.width
        visible: root._inputs.length > 0
        spacing: Theme.space.rowGap

        SectionLabel {
            leftPadding: Theme.space.controlPaddingX
            text: "INPUT"
            count: root._inputPick ? root._inputs.length : root._inputRows.length
        }

        ButtonGroup {
            id: inputPickGroup
            visible: root._inputPick
            width: parent.width
            options: root._inputOptions
            index: root._inputSelected
            cursor: root.cursorActive && root._cursorKey === "input-pick"
            onChanged: index => root._makeDefault({ node: root._inputs[index], isOutput: false })
            onHovered: (index, isHovered) => {
                if (!isHovered)
                    return;
                root._pointAt("input-pick");
                inputPickGroup.cursorIndex = index;
            }
        }

        Column {
            width: parent.width
            spacing: 0

            Repeater {
                model: root._inputRows
                delegate: deviceRow
            }
        }
    }

    Column {
        width: parent.width
        visible: root._streamRows.length > 0
        spacing: Theme.space.rowGap

        SectionLabel {
            leftPadding: Theme.space.controlPaddingX
            text: "APPS"
            count: root._streamRows.length
        }

        Column {
            width: parent.width
            spacing: 0

            Repeater {
                model: root._streamRows
                delegate: streamRow
            }
        }
    }
}

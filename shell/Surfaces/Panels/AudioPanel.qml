import QtQuick
import Quickshell.Services.Pipewire
import qs.Core
import qs.Components
import "../../Audio/model.js" as AudioModel

// The shared PanelHero (M26 Task 1) opens the panel with the default
// sink's own name, mute state, volume percent and rail, mute as its
// trailing toggle (M28 Task 1). Omarchy mixer behavior below it (DESIGN.md
// §Panels, spec §2, M6 Task 1; M15 Task 4): one selectable row per
// candidate output sink (click/Enter sets Pipewire.preferredDefaultAudioSink,
// the active row inverted); INPUT pairs its own noun with its percent and
// mute on one header line, track underneath, then the same selectable rows
// for sources, the whole section omitted when no input hardware exists;
// APPS lists real playback streams
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

    readonly property bool _outputMuted: root._sink !== null && root._sink.audio !== null && root._sink.audio.muted
    readonly property real _outputVolume: root._sink !== null && root._sink.audio !== null
        ? AudioModel.clampDevice(root._sink.audio.volume) : 0

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

    // Cursor identity starts on the first row every open (audio devices can
    // change while the panel was closed) so the M26 Task 8 reveal-only
    // guard above has a real position to show, never an empty key that
    // would gate `hovered` false on the first press.
    onIsOpenChanged: {
        if (root.isOpen)
            root._cursorKey = root._cursorEntries.length > 0 ? root._cursorEntries[0].key : "";
        else
            root._cursorKey = "";
    }

    // Panel.qml's shared keyboard-nav hook (M6 Task 7, PowerPanel/
    // NetworkPanel's consumer pattern): Up/Down move the cursor, h/l step
    // whatever slider it's on by 5%, m mutes, Enter activates.
    Connections {
        target: root

        function onKeyPressed(event) {
            if (!root.isOpen)
                return;
            // First Up/Down only reveals the cursor where it already sits
            // (M26 Task 8, upstream's CursorSurface contract) — it does not
            // also move it, so the highlight appears where the user can see
            // it before anything happens.
            if (!root.cursorActive && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                root.cursorActive = true;
                event.accepted = true;
                return;
            }
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
            hovered: root.cursorActive && root._cursorKey === deviceCell.modelData.cursorKey
            onContainsPointerChanged: if (deviceCell.containsPointer) {
                root.cursorActive = true;
                root._cursorKey = deviceCell.modelData.cursorKey;
            }

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
            interactive: true
            hovered: root.cursorActive && root._cursorKey === streamCell.modelData.cursorKey
            onContainsPointerChanged: if (streamCell.containsPointer) {
                root.cursorActive = true;
                root._cursorKey = streamCell.modelData.cursorKey;
            }

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

                // Same header-line rhythm as the hero and the INPUT row
                // above: the app's own name left, its percent and mute
                // right, one line, track underneath.
                Item {
                    width: parent.width
                    height: Math.max(streamLabelText.implicitHeight, streamValueRow.implicitHeight)

                    Text {
                        id: streamLabelText
                        text: streamCell._label
                        color: streamCell.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.body
                        elide: Text.ElideRight
                        anchors.left: parent.left
                        anchors.right: streamValueRow.left
                        anchors.rightMargin: Theme.space.sm
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Row {
                        id: streamValueRow
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space.sm

                        Text {
                            id: streamPercent
                            text: Math.round(streamCell._volume * 100) + "%"
                            color: streamCell._muted ? Theme.color.foregroundFaint : streamCell.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize.caption
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Bare-label ink promotion (DESIGN.md §1.1's
                        // 2026-08-09 amendment): no cell chrome, armed
                        // state promotes straight to accent instead of a
                        // fill/inversion.
                        MetaLabel {
                            id: streamMuteLabel
                            text: "MUTE"
                            color: streamCell._muted
                                ? Theme.color.accent
                                : (streamMuteHover.containsMouse ? Theme.color.foreground : Theme.color.foregroundDim)
                            anchors.verticalCenter: parent.verticalCenter

                            MouseArea {
                                id: streamMuteHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (streamCell._audio) streamCell._audio.muted = !streamCell._audio.muted
                            }
                        }
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

    // The panel's own subject: the default sink's name, mute state, volume
    // and rail, with mute promoted into the trailing slot (M28 Task 1).
    // Replaces the old OUTPUT header row and its master slider outright, so
    // the output device list below opens directly on this.
    PanelHero {
        visible: root._sink !== null && root._sink.audio !== null
        width: parent.width
        glyph: root._outputMuted ? "󰝟" : "󰕾"
        title: root._sink ? (root._sink.description || root._sink.name) : ""
        meta: root._outputMuted ? "MUTED" : "ACTIVE"
        readout: Math.round(root._outputVolume * 100) + "%"
        rail: root._outputVolume
        // No pointer on the hero (the rail is a readout, not a control),
        // but the keyboard cursor still lands on "output-slider" for h/l —
        // this is its only visual trace.
        hovered: root.cursorActive && root._cursorKey === "output-slider"
        trailing: outputMuteToggle
    }

    Component {
        id: outputMuteToggle

        MetaLabel {
            text: "MUTE"
            color: root._outputMuted
                ? Theme.color.accent
                : (outputMuteHover.containsMouse ? Theme.color.foreground : Theme.color.foregroundDim)

            MouseArea {
                id: outputMuteHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root._sink && root._sink.audio) root._sink.audio.muted = !root._sink.audio.muted
            }
        }
    }

    Cell {
        visible: root._outputs.length === 0 && root._inputs.length === 0
        width: parent.width

        MetaLabel { text: "NO DEVICES" }
    }

    Repeater {
        model: root._outputRows
        delegate: deviceRow
    }

    // Header-line pairing (upstream's own idiom, adopted M28 Task 1): the
    // section noun sits left, its readout and mute right, on one line,
    // track underneath — one row saved over a separate "INPUT:" header.
    Cell {
        id: inputMasterCell
        visible: root._inputs.length > 0
        interactive: true
        hovered: root.cursorActive && root._cursorKey === "input-slider"
        onContainsPointerChanged: if (inputMasterCell.containsPointer) {
            root.cursorActive = true;
            root._cursorKey = "input-slider";
        }
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.space.xxs

            Item {
                width: parent.width
                height: Math.max(inputHeaderLabel.implicitHeight, inputValueRow.implicitHeight)

                MetaLabel {
                    id: inputHeaderLabel
                    text: "INPUT"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    id: inputValueRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space.sm

                    Text {
                        text: Math.round((root._source && root._source.audio ? root._source.audio.volume : 0) * 100) + "%"
                        color: inputMasterCell.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.body
                    }

                    MetaLabel {
                        id: inputMuteLabel
                        text: "MUTE"
                        color: (root._source && root._source.audio && root._source.audio.muted)
                            ? Theme.color.accent
                            : (inputMuteHover.containsMouse ? Theme.color.foreground : Theme.color.foregroundDim)

                        MouseArea {
                            id: inputMuteHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root._source && root._source.audio) root._source.audio.muted = !root._source.audio.muted
                        }
                    }
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

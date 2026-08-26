import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../Airpods/model.js" as AirpodsModel

// AirPods panel (DESIGN.md §3 "Panel", spec "Panels"): the popout behind
// AirpodsWidget's bar cell, bound to AirpodsService, which watches the
// omarchy-pods librepods daemon's status.json and owns its control socket.
// This panel reads `status` and calls `send(verb)`, and registers as a
// rewatch consumer for as long as it is open (acquire()/release()), so a
// daemonless host never pays for a panel that is opened but never used to
// find one.
//
// Honest states first: no status.json at all (the daemon is not running, or
// quit and removed it) renders one dim NO DAEMON row; a live daemon that
// has never seen a battery packet and reports the link down renders NO
// AIRPODS, since the file existing only proves the daemon is up, not that
// earbuds are anywhere near it. Past those two gates the hero opens on the
// device's own name and AirpodsModel.stateLine(), and BATTERY is a row per
// component with a known level, never an invented single readout.
//
// LISTENING MODE and the two Pro toggles are gated on `connected`: control
// verbs only mean something with the L2CAP link up. Ear detection is
// host-side daemon policy and stays visible whenever anything about the
// device is known at all, in-case included.
//
// Keyboard (spec "Keyboard model"): one cursor walks the actionable stops
// in visual order, the listening-mode group, the adaptive track, the two
// toggles, then the ear-detection group. On a group stop Left and Right
// walk the buttons inside it and Enter presses the one under the ring; on
// the adaptive track they step the level by 5, the same move the track's
// own wheel makes. The cursor is keyed by stop identity rather than by
// index (AudioPanel's idiom): a section that appears mid-session must not
// slide the highlight onto a different stop.
Panel {
    id: root

    panelIcon: "headphones"
    panelTitle: "AirPods"
    panelWidth: Theme.space.popupWidthWide

    readonly property var _status: AirpodsService.status
    readonly property var _batteryRows: AirpodsModel.batteryRows(root._status)
    readonly property var _modes: AirpodsModel.modesFor(root._status)
    readonly property bool _hasKnownState: root._status.connected || root._batteryRows.length > 0
    readonly property bool _noDaemon: !AirpodsService.available
    readonly property bool _noAirpods: !root._noDaemon && !root._hasKnownState
    readonly property bool _heroVisible: !root._noDaemon && !root._noAirpods
    readonly property bool _controlsVisible: root._heroVisible && root._status.connected
    readonly property bool _togglesVisible: root._controlsVisible && root._status.isPro
    readonly property bool _adaptiveVisible: root._controlsVisible && root._status.noiseMode === AirpodsModel.NoiseMode.Adaptive

    readonly property string _heroTitle: root._status.deviceName !== "" ? root._status.deviceName : "AirPods"

    // Keyed the way modesFor() keys its rows: the list gains and loses Off
    // and Adaptive per model, so a positional array would pair the wrong
    // glyph with the wrong mode.
    readonly property var _modeIcons: ({
        "off": "circle-off",
        "anc": "ear-off",
        "transparency": "ear",
        "adaptive": "audio-waveform"
    })

    readonly property var _modeOptions: root._modes.map(function (mode) {
        return { icon: root._modeIcons[mode.key], label: mode.label, value: mode.verb, active: mode.active };
    })

    // -1 while the daemon reports no noise mode, which leaves the group with
    // no selected button instead of pointing at Off.
    readonly property int _activeModeIndex: {
        for (var i = 0; i < root._modes.length; i++)
            if (root._modes[i].active)
                return i;
        return -1;
    }

    // Position matches the daemon's own ear_detection_behavior numbering
    // (0 one out, 1 both out, 2 never), so `index` binds straight to it.
    readonly property var _earOptions: [
        { label: "One", value: "ear:one" },
        { label: "Both", value: "ear:both" },
        { label: "Off", value: "ear:off" }
    ]

    readonly property var _cursorEntries: {
        var out = [];
        if (root._controlsVisible) {
            out.push({ key: "modes", kind: "group" });
            if (root._adaptiveVisible)
                out.push({ key: "adaptive", kind: "adaptive" });
            if (root._togglesVisible) {
                out.push({ key: "ca", kind: "ca" });
                out.push({ key: "onebud", kind: "onebud" });
            }
        }
        if (root._heroVisible)
            out.push({ key: "ear", kind: "group" });
        return out;
    }

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

    function _toggleCa() {
        AirpodsService.send(root._status.conversationalAwareness ? "ca:off" : "ca:on");
    }

    function _toggleOneBud() {
        AirpodsService.send(root._status.oneBudAnc ? "onebud:off" : "onebud:on");
    }

    function _setAdaptive(level) {
        AirpodsService.send("adaptive:" + Math.round(Math.max(0, Math.min(100, level))));
    }

    function _groupFor(key) {
        if (key === "modes")
            return modeGroup;
        if (key === "ear")
            return earGroup;
        return null;
    }

    // The groups are controlled, so a press writes the verb and moves only
    // the ring; `index` follows once the daemon reports the new state back.
    function _pressGroup(group, index) {
        var verb = group.valueAt(index);
        if (verb === undefined)
            return;
        group.cursorIndex = index;
        AirpodsService.send(verb);
    }

    cursorCount: root._cursorEntries.length
    // Left/Right belongs to whatever the cursor sits on, a group's buttons
    // or the adaptive track, not to the list: a single column already walks
    // with Up/Down.
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
        if (entry.kind === "group")
            root._groupFor(entry.key).activate();
        else if (entry.kind === "ca")
            root._toggleCa();
        else if (entry.kind === "onebud")
            root._toggleOneBud();
    }

    onCursorStepped: (index, direction) => {
        var entry = root._entryAt(index);
        if (!entry)
            return;
        if (entry.kind === "group")
            root._groupFor(entry.key).step(direction);
        else if (entry.kind === "adaptive")
            root._setAdaptive(root._status.adaptiveNoiseLevel + direction * 5);
    }

    onIsOpenChanged: {
        if (root.isOpen) {
            root.cursorIndex = 0;
            root.cursorSection = 0;
            root._cursorKey = root._keyAt(0);
            // Each ring starts on what is already selected, so the
            // reveal-only first keypress shows it where the eye is.
            modeGroup.cursorIndex = Math.max(0, root._activeModeIndex);
            earGroup.cursorIndex = Math.max(0, root._status.earDetection);
            AirpodsService.acquire();
        } else {
            root._cursorKey = "";
            AirpodsService.release();
        }
    }

    SectionLabel {
        visible: root._noDaemon
        leftPadding: Theme.space.controlPaddingX
        text: "NO DAEMON"
    }

    SectionLabel {
        visible: root._noAirpods
        leftPadding: Theme.space.controlPaddingX
        text: "NO AIRPODS"
    }

    PanelHero {
        id: deviceHero
        visible: root._heroVisible
        width: parent.width
        title: root._heroTitle
        meta: AirpodsModel.stateLine(root._status)

        leading: Component {
            Icon {
                name: "headphones"
                size: Theme.fontSize.heading
                color: deviceHero.foreground
            }
        }
    }

    Component {
        id: batteryRow

        Cell {
            id: battCell
            required property var modelData
            width: parent.width
            ghost: true

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                Item {
                    width: parent.width
                    height: Math.max(battLabel.implicitHeight, battValueRow.implicitHeight)

                    Text {
                        id: battLabel
                        anchors.left: parent.left
                        anchors.right: battValueRow.left
                        anchors.rightMargin: Theme.space.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        text: battCell.modelData.label
                        color: battCell.foreground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                        elide: Text.ElideRight
                    }

                    Row {
                        id: battValueRow
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space.iconGap

                        SectionLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: battCell.modelData.hint !== ""
                            text: battCell.modelData.hint
                            color: battCell.dimForeground
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: battCell.modelData.level + "%"
                            color: battCell.foreground
                            font.family: Theme.fontFamilyMono
                            font.pixelSize: Theme.fontSize.body
                            font.weight: Theme.weight.medium
                        }
                    }
                }

                Track {
                    width: parent.width
                    value: battCell.modelData.level / 100
                }
            }
        }
    }

    Column {
        width: parent.width
        visible: root._batteryRows.length > 0
        spacing: Theme.space.rowGap

        SectionLabel { leftPadding: Theme.space.controlPaddingX; text: "BATTERY" }

        // A borderless row leaves no box for a gap to sit between, so the rows
        // in a section abut and only `sectionGap` separates the sections.
        Column {
            width: parent.width
            spacing: 0

            Repeater {
                model: root._batteryRows
                delegate: batteryRow
            }
        }
    }

    Column {
        width: parent.width
        visible: root._controlsVisible
        spacing: Theme.space.rowGap

        SectionLabel { leftPadding: Theme.space.controlPaddingX; text: "LISTENING MODE" }

        ButtonGroup {
            id: modeGroup
            width: parent.width
            options: root._modeOptions
            index: root._activeModeIndex
            cursor: root.cursorActive && root._cursorKey === "modes"
            onChanged: index => root._pressGroup(modeGroup, index)
            onHovered: (index, isHovered) => {
                if (!isHovered)
                    return;
                root._pointAt("modes");
                modeGroup.cursorIndex = index;
            }
        }

        // The adaptive level belongs to the Adaptive mode above it, so it
        // sits inside that section rather than opening one of its own.
        Cell {
            id: adaptiveCell
            visible: root._adaptiveVisible
            width: parent.width
            ghost: true
            cursor: root.cursorActive && root._cursorKey === "adaptive"
            interactive: true
            acceptedButtons: Qt.NoButton
            onContainsPointerChanged: if (adaptiveCell.containsPointer) root._pointAt("adaptive")

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                Item {
                    width: parent.width
                    height: Math.max(adaptiveLabel.implicitHeight, adaptivePercent.implicitHeight)

                    Text {
                        id: adaptiveLabel
                        anchors.left: parent.left
                        anchors.right: adaptivePercent.left
                        anchors.rightMargin: Theme.space.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Adaptive noise"
                        color: adaptiveCell.foreground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                        elide: Text.ElideRight
                    }

                    Text {
                        id: adaptivePercent
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._status.adaptiveNoiseLevel + "%"
                        color: adaptiveCell.foreground
                        font.family: Theme.fontFamilyMono
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                    }
                }

                Track {
                    id: adaptiveTrack
                    width: parent.width
                    value: root._status.adaptiveNoiseLevel / 100

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function _setFromX(x) {
                            root._setAdaptive((x / adaptiveTrack.width) * 100);
                        }
                        onPressed: mouse => _setFromX(mouse.x)
                        onPositionChanged: mouse => { if (pressed) _setFromX(mouse.x); }
                        onWheel: wheel => {
                            root._setAdaptive(root._status.adaptiveNoiseLevel + (wheel.angleDelta.y > 0 ? 5 : -5));
                            wheel.accepted = true;
                        }
                    }
                }
            }
        }
    }

    Column {
        width: parent.width
        visible: root._togglesVisible
        spacing: Theme.space.rowGap

        SectionLabel { leftPadding: Theme.space.controlPaddingX; text: "OPTIONS" }

        Column {
            width: parent.width
            spacing: 0

            Cell {
                id: caCell
                width: parent.width
                ghost: true
                cursor: root.cursorActive && root._cursorKey === "ca"
                interactive: true
                onContainsPointerChanged: if (caCell.containsPointer) root._pointAt("ca")
                onClicked: root._toggleCa()

                Item {
                    width: parent.width
                    height: Math.max(caColumn.implicitHeight, caButton.height)

                    Column {
                        id: caColumn
                        anchors.left: parent.left
                        anchors.right: caButton.left
                        anchors.rightMargin: Theme.space.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space.xxs

                        Text {
                            width: parent.width
                            text: "Conversation awareness"
                            color: caCell.foreground
                            font.family: Theme.fontFamilySans
                            font.pixelSize: Theme.fontSize.body
                            font.weight: Theme.weight.medium
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: "Lowers volume when you talk"
                            color: caCell.dimForeground
                            font.family: Theme.fontFamilySans
                            font.pixelSize: Theme.fontSize.bodySmall
                            elide: Text.ElideRight
                        }
                    }

                    // An on/off state is a `Switch` (DESIGN.md §2), never a
                    // button whose label is the state. Enter on the row calls
                    // the same `_toggleCa`, so keyboard and pointer say one
                    // thing.
                    Switch {
                        id: caButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: root._status.conversationalAwareness
                        onToggled: root._toggleCa()
                    }
                }
            }

            Cell {
                id: oneBudCell
                width: parent.width
                ghost: true
                cursor: root.cursorActive && root._cursorKey === "onebud"
                interactive: true
                onContainsPointerChanged: if (oneBudCell.containsPointer) root._pointAt("onebud")
                onClicked: root._toggleOneBud()

                Item {
                    width: parent.width
                    height: Math.max(oneBudColumn.implicitHeight, oneBudButton.height)

                    Column {
                        id: oneBudColumn
                        anchors.left: parent.left
                        anchors.right: oneBudButton.left
                        anchors.rightMargin: Theme.space.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space.xxs

                        Text {
                            width: parent.width
                            text: "One-bud ANC"
                            color: oneBudCell.foreground
                            font.family: Theme.fontFamilySans
                            font.pixelSize: Theme.fontSize.body
                            font.weight: Theme.weight.medium
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: "Keeps ANC with one pod in"
                            color: oneBudCell.dimForeground
                            font.family: Theme.fontFamilySans
                            font.pixelSize: Theme.fontSize.bodySmall
                            elide: Text.ElideRight
                        }
                    }

                    Switch {
                        id: oneBudButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: root._status.oneBudAnc
                        onToggled: root._toggleOneBud()
                    }
                }
            }
        }
    }

    Column {
        width: parent.width
        visible: root._heroVisible
        spacing: Theme.space.rowGap

        SectionLabel { leftPadding: Theme.space.controlPaddingX; text: "EAR DETECTION" }

        ButtonGroup {
            id: earGroup
            width: parent.width
            options: root._earOptions
            index: root._status.earDetection
            cursor: root.cursorActive && root._cursorKey === "ear"
            onChanged: index => root._pressGroup(earGroup, index)
            onHovered: (index, isHovered) => {
                if (!isHovered)
                    return;
                root._pointAt("ear");
                earGroup.cursorIndex = index;
            }
        }
    }
}

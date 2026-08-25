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
// Keyboard (spec "Keyboard model"): one cursor walks every actionable row
// in visual order, the listening modes, the adaptive track, the two
// toggles, then ear detection. Enter applies the mode or flips the toggle
// under it; Left/Right steps the adaptive level by 5, the same move the
// track's own wheel makes. The cursor is keyed by row identity rather than
// by index (AudioPanel's idiom): a mode list that grows an Adaptive entry
// mid-session must not slide the highlight onto a different row.
Panel {
    id: root

    panelIcon: "headphones"
    panelTitle: "AirPods"
    panelWidth: Theme.space.popupWidthDefault

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

    readonly property var _cursorEntries: {
        var out = [];
        if (root._controlsVisible) {
            for (var i = 0; i < root._modes.length; i++)
                out.push({ key: "mode:" + root._modes[i].key, kind: "mode", mode: root._modes[i] });
            if (root._adaptiveVisible)
                out.push({ key: "adaptive", kind: "adaptive" });
            if (root._togglesVisible) {
                out.push({ key: "ca", kind: "ca" });
                out.push({ key: "onebud", kind: "onebud" });
            }
        }
        if (root._heroVisible)
            out.push({ key: "ear", kind: "ear" });
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

    // 0 (pause when one out) -> 1 (when both out) -> 2 (never) -> 0, the
    // same cycle the daemon's three `ear:*` verbs name in order.
    function _cycleEar() {
        var verbs = ["ear:one", "ear:both", "ear:off"];
        var next = (root._status.earDetection + 1) % 3;
        AirpodsService.send(verbs[next]);
    }

    cursorCount: root._cursorEntries.length
    // Left/Right belongs to the adaptive track under the cursor, not to the
    // list: a single column already walks with Up/Down.
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
        if (entry.kind === "mode")
            AirpodsService.send(entry.mode.verb);
        else if (entry.kind === "ca")
            root._toggleCa();
        else if (entry.kind === "onebud")
            root._toggleOneBud();
        else if (entry.kind === "ear")
            root._cycleEar();
    }

    onCursorStepped: (index, direction) => {
        var entry = root._entryAt(index);
        if (!entry || entry.kind !== "adaptive")
            return;
        root._setAdaptive(root._status.adaptiveNoiseLevel + direction * 5);
    }

    onIsOpenChanged: {
        if (root.isOpen) {
            root.cursorIndex = 0;
            root.cursorSection = 0;
            root._cursorKey = root._keyAt(0);
            AirpodsService.acquire();
        } else {
            root._cursorKey = "";
            AirpodsService.release();
        }
    }

    Cell {
        visible: root._noDaemon
        width: parent.width

        SectionLabel { text: "NO DAEMON" }
    }

    Cell {
        visible: root._noAirpods
        width: parent.width

        SectionLabel { text: "NO AIRPODS" }
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

        SectionLabel { text: "BATTERY" }

        Repeater {
            model: root._batteryRows
            delegate: batteryRow
        }
    }

    Component {
        id: modeRow

        Cell {
            id: modeCell
            required property var modelData
            readonly property string _key: "mode:" + modeCell.modelData.key
            width: parent.width
            selected: modeCell.modelData.active
            cursor: root.cursorActive && root._cursorKey === modeCell._key
            interactive: true
            onContainsPointerChanged: if (modeCell.containsPointer) root._pointAt(modeCell._key)
            onClicked: AirpodsService.send(modeCell.modelData.verb)

            Item {
                width: parent.width
                height: modeLabel.implicitHeight

                Text {
                    id: modeLabel
                    anchors.left: parent.left
                    anchors.right: modeCheck.left
                    anchors.rightMargin: Theme.space.iconGap
                    anchors.verticalCenter: parent.verticalCenter
                    text: modeCell.modelData.label
                    color: modeCell.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                    elide: Text.ElideRight
                }

                Icon {
                    id: modeCheck
                    name: "check"
                    size: Theme.fontSize.body
                    visible: modeCell.selected
                    color: Theme.color.primary
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Column {
        width: parent.width
        visible: root._controlsVisible
        spacing: Theme.space.rowGap

        SectionLabel { text: "LISTENING MODE" }

        Repeater {
            model: root._controlsVisible ? root._modes : []
            delegate: modeRow
        }

        // The adaptive level belongs to the Adaptive mode above it, so it
        // sits inside that section rather than opening one of its own.
        Cell {
            id: adaptiveCell
            visible: root._adaptiveVisible
            width: parent.width
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
        visible: root._heroVisible
        spacing: Theme.space.rowGap

        SectionLabel { text: "OPTIONS" }

        Cell {
            id: caCell
            visible: root._togglesVisible
            width: parent.width
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

                Button {
                    id: caButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    variant: root._status.conversationalAwareness ? "default" : "outline"
                    text: root._status.conversationalAwareness ? "On" : "Off"
                    onClicked: root._toggleCa()
                }
            }
        }

        Cell {
            id: oneBudCell
            visible: root._togglesVisible
            width: parent.width
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

                Button {
                    id: oneBudButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    variant: root._status.oneBudAnc ? "default" : "outline"
                    text: root._status.oneBudAnc ? "On" : "Off"
                    onClicked: root._toggleOneBud()
                }
            }
        }

        Cell {
            id: earCell
            visible: root._heroVisible
            width: parent.width
            cursor: root.cursorActive && root._cursorKey === "ear"
            interactive: true
            onContainsPointerChanged: if (earCell.containsPointer) root._pointAt("ear")
            onClicked: root._cycleEar()

            Item {
                width: parent.width
                height: Math.max(earLabel.implicitHeight, earValue.implicitHeight)

                SectionLabel {
                    id: earLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "EAR DETECTION"
                }

                // Bounded on both sides, not just right-anchored: the
                // longest earDetectionLabel() string does not fit beside
                // the label at this width, and a right-aligned Text wider
                // than its own box overflows left, back over the label.
                Text {
                    id: earValue
                    anchors.left: earLabel.right
                    anchors.leftMargin: Theme.space.iconGap
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: AirpodsModel.earDetectionLabel(root._status.earDetection)
                    color: earCell.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                    elide: Text.ElideRight
                }
            }
        }
    }
}

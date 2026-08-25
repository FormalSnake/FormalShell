import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../Airpods/model.js" as AirpodsModel

// AirPods panel (M29 Task 2, plan at
// docs/superpowers/plans/2026-08-18-m29-device-panels.md): a dedicated
// popout for the omarchy-pods librepods daemon, replacing the old M17
// "AIRPODS NOISE" group bolted onto the bottom of BluetoothPanel. Bound
// directly to AirpodsService (Services/AirpodsService.qml, M29 Task 1),
// which itself watches the daemon's status.json and owns the control
// socket — this panel reads `status` and calls `send(verb)`, and registers
// as a rewatch consumer for as long as it's open (acquire()/release(),
// DualsensePanel.qml's own onIsOpenChanged idiom) so a daemonless host
// never pays for a panel that's opened but never used to find one.
//
// Honest states first: no status.json at all (the daemon isn't running, or
// quit and removed it) renders one dim "NO DAEMON" cell; a live daemon that
// has never seen a battery packet and reports the link down renders
// "NO AIRPODS" — the file existing only proves the daemon is up, not that
// earbuds are anywhere near it. Past those two gates, PanelHero opens on
// the device's own name and AirpodsModel.stateLine(); battery is a list of
// up to three rows, never an invented single readout (DESIGN.md §2.13).
// LISTENING MODE and the two Pro toggles are gated on `connected` — control
// verbs only mean something with the L2CAP link up — while EAR DETECTION
// is host-side daemon policy (plan's research block) and stays visible
// whenever anything about the device is known at all, in-case included.
//
// One flat keyboard cursor (`_cursorKey`) walks every actionable row —
// listening modes, the two toggles, ear detection — mirroring
// BluetoothPanel's address-keyed cursor and AudioPanel's cursorKey one;
// the adaptive-noise track is mouse/wheel only, PowerPanel's brightness-row
// precedent for a slider that isn't a discrete choice.
Panel {
    id: root

    panelTitle: "AIRPODS"
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

    function _toggleCa() {
        AirpodsService.send(root._status.conversationalAwareness ? "ca:off" : "ca:on");
    }

    function _toggleOneBud() {
        AirpodsService.send(root._status.oneBudAnc ? "onebud:off" : "onebud:on");
    }

    // 0 (pause when one out) -> 1 (when both out) -> 2 (never) -> 0, the
    // same cycle the daemon's three `ear:*` verbs name in order.
    function _cycleEar() {
        var verbs = ["ear:one", "ear:both", "ear:off"];
        var next = (root._status.earDetection + 1) % 3;
        AirpodsService.send(verbs[next]);
    }

    function _activateCursor() {
        var entry = root._cursorEntry();
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

    onIsOpenChanged: {
        if (root.isOpen) {
            root._cursorKey = root._cursorEntries.length > 0 ? root._cursorEntries[0].key : "";
            AirpodsService.acquire();
        } else {
            root._cursorKey = "";
            AirpodsService.release();
        }
    }

    // Panel.qml's shared keyboard-nav hook (M6 Task 7, BluetoothPanel.qml's
    // consumer pattern): Up/Down move the cursor, Enter activates it, first
    // Up/Down only reveals the cursor where it already sits (M26 Task 8).
    Connections {
        target: root

        function onKeyPressed(event) {
            if (!root.isOpen)
                return;
            if (!root.cursorActive && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                root.cursorActive = true;
                event.accepted = true;
                return;
            }
            switch (event.key) {
            case Qt.Key_Up:
                root._moveCursor(-1);
                event.accepted = true;
                break;
            case Qt.Key_Down:
                root._moveCursor(1);
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root._activateCursor();
                event.accepted = true;
                break;
            }
        }
    }

    Cell {
        visible: root._noDaemon
        width: parent.width

        MetaLabel { text: "NO DAEMON" }
    }

    Cell {
        visible: root._noAirpods
        width: parent.width

        MetaLabel { text: "NO AIRPODS" }
    }

    PanelHero {
        visible: root._heroVisible
        width: parent.width
        glyph: "󱡏"
        title: root._heroTitle
        meta: AirpodsModel.stateLine(root._status)
    }

    Cell {
        visible: root._batteryRows.length > 0
        width: parent.width

        MetaLabel { text: "BATTERY"; colon: true }
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

                Row {
                    width: parent.width
                    spacing: Theme.space.sm

                    Text {
                        width: parent.width - valueRow.width - parent.spacing
                        text: battCell.modelData.label
                        color: battCell.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.body
                        elide: Text.ElideRight
                    }

                    Row {
                        id: valueRow
                        spacing: Theme.space.sm

                        Text {
                            text: battCell.modelData.level + "%"
                            color: battCell.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize.body
                        }

                        MetaLabel {
                            visible: battCell.modelData.hint !== ""
                            text: battCell.modelData.hint
                        }
                    }
                }

                DitherFill {
                    width: parent.width
                    height: Theme.space.trackThickness

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, battCell.modelData.level / 100))
                        height: parent.height
                        color: Theme.color.primary
                    }
                }
            }
        }
    }

    Repeater {
        model: root._batteryRows
        delegate: batteryRow
    }

    Cell {
        visible: root._controlsVisible
        width: parent.width

        MetaLabel { text: "LISTENING MODE"; colon: true }
    }

    Component {
        id: modeRow

        Cell {
            id: modeCell
            required property var modelData
            readonly property string _key: "mode:" + modeCell.modelData.key
            width: parent.width
            selected: modeCell.modelData.active
            hovered: root.cursorActive && root._cursorKey === modeCell._key
            onContainsPointerChanged: if (modeCell.containsPointer) {
                root.cursorActive = true;
                root._cursorKey = modeCell._key;
            }

            ActionLabel {
                text: modeCell.modelData.label
                color: modeCell.foreground
            }

            interactive: true
            onClicked: AirpodsService.send(modeCell.modelData.verb)
        }
    }

    Repeater {
        model: root._controlsVisible ? root._modes : []
        delegate: modeRow
    }

    Cell {
        visible: root._adaptiveVisible
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.space.xxs

            Row {
                width: parent.width
                spacing: Theme.space.sm

                Text {
                    width: parent.width - adaptivePercent.width - parent.spacing
                    text: "Adaptive Noise"
                    color: Theme.color.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }

                Text {
                    id: adaptivePercent
                    text: root._status.adaptiveNoiseLevel + "%"
                    color: Theme.color.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }
            }

            DitherFill {
                id: adaptiveTrack
                width: parent.width
                height: Theme.space.trackThickness

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root._status.adaptiveNoiseLevel / 100))
                    height: parent.height
                    color: Theme.color.primary
                }

                MouseArea {
                    anchors.fill: parent
                    function _setFromX(x) {
                        var level = Math.round(Math.max(0, Math.min(1, x / adaptiveTrack.width)) * 100);
                        AirpodsService.send("adaptive:" + level);
                    }
                    onPressed: mouse => _setFromX(mouse.x)
                    onPositionChanged: mouse => { if (pressed) _setFromX(mouse.x); }
                    onWheel: wheel => {
                        var level = Math.max(0, Math.min(100, root._status.adaptiveNoiseLevel + (wheel.angleDelta.y > 0 ? 5 : -5)));
                        AirpodsService.send("adaptive:" + level);
                        wheel.accepted = true;
                    }
                }
            }
        }
    }

    // The two Pro-only toggles (DESIGN.md §1.1's bare-label ink-promotion
    // amendment for the ON/OFF piece; the row itself is a full cursor-
    // navigable Cell so the fill it lights up on hover is also the whole
    // hit area, §1.1's 2026-08-14 amendment). Two hand-written cells, not
    // a shared delegate — there are exactly two of them and they differ in
    // copy, key and armed source, not in shape.
    Cell {
        id: caCell
        visible: root._togglesVisible
        width: parent.width
        hovered: root.cursorActive && root._cursorKey === "ca"
        onContainsPointerChanged: if (caCell.containsPointer) {
            root.cursorActive = true;
            root._cursorKey = "ca";
        }

        Row {
            width: parent.width
            spacing: Theme.space.sm

            Column {
                width: parent.width - caState.width - parent.spacing
                spacing: Theme.space.xxs

                Text {
                    width: parent.width
                    text: "Conversation awareness"
                    color: caCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                    elide: Text.ElideRight
                }

                MetaLabel {
                    width: parent.width
                    text: "LOWERS VOLUME WHEN YOU TALK"
                    color: caCell.dimForeground
                    elide: Text.ElideRight
                }
            }

            MetaLabel {
                id: caState
                text: root._status.conversationalAwareness ? "ON" : "OFF"
                color: root._status.conversationalAwareness ? Theme.color.primary : caCell.dimForeground
            }
        }

        interactive: true
        onClicked: root._toggleCa()
    }

    Cell {
        id: oneBudCell
        visible: root._togglesVisible
        width: parent.width
        hovered: root.cursorActive && root._cursorKey === "onebud"
        onContainsPointerChanged: if (oneBudCell.containsPointer) {
            root.cursorActive = true;
            root._cursorKey = "onebud";
        }

        Row {
            width: parent.width
            spacing: Theme.space.sm

            Column {
                width: parent.width - oneBudState.width - parent.spacing
                spacing: Theme.space.xxs

                Text {
                    width: parent.width
                    text: "One-bud ANC"
                    color: oneBudCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                    elide: Text.ElideRight
                }

                MetaLabel {
                    width: parent.width
                    text: "KEEPS ANC WITH ONE POD IN"
                    color: oneBudCell.dimForeground
                    elide: Text.ElideRight
                }
            }

            MetaLabel {
                id: oneBudState
                text: root._status.oneBudAnc ? "ON" : "OFF"
                color: root._status.oneBudAnc ? Theme.color.primary : oneBudCell.dimForeground
            }
        }

        interactive: true
        onClicked: root._toggleOneBud()
    }

    Cell {
        id: earCell
        visible: root._heroVisible
        width: parent.width
        hovered: root.cursorActive && root._cursorKey === "ear"
        onContainsPointerChanged: if (earCell.containsPointer) {
            root.cursorActive = true;
            root._cursorKey = "ear";
        }

        // Stacked, not a label/value Row: the longest earDetectionLabel()
        // string ("PAUSE WHEN ONE IS OUT") doesn't fit beside the header at
        // panelWidth, and a right-aligned Text wider than its own box
        // overflows LEFT, straight back over the label — caught in this
        // row's own M29 smoke screenshot.
        Column {
            width: parent.width
            spacing: Theme.space.xxs

            MetaLabel {
                text: "EAR DETECTION"
                colon: true
            }

            Text {
                width: parent.width
                text: AirpodsModel.earDetectionLabel(root._status.earDetection)
                color: earCell.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }
        }

        interactive: true
        onClicked: root._cycleEar()
    }
}

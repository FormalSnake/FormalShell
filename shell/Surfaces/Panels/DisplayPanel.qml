import QtQuick
import qs.Core
import qs.Components
import qs.Compositor
import qs.Services
import "../../Display/outputs.js" as Outputs

// Display panel (DESIGN.md §Panels, M17): a ledger of every connected output
// — one row each, the focused one inverted — carrying the three things the
// owner asked for, on/off, scale, and mirror. Feature shape read off
// omarchy's monitor panel (shell/plugins/panels/monitor/Panel.qml there:
// internalMonitor/externalMonitor/internalEnabled/mirrorEnabled/monitorScale/
// displays) and reimplemented in this shell's own language.
//
// BRIGHTNESS (M33, owner reversal of the M16 call above: "move the display
// things from battery to display, it makes no sense they were merged
// anyway") sits between OUTPUTS and MIRROR — one row per BrightnessService
// device, sharing this panel's own Up/Down cursor and h/l steps rather than
// a separate hover system, since a second keyboard cursor on the same panel
// would double-drive whichever row both happened to point at. The cursor
// walks outputs first, then brightness devices, in the same top-to-bottom
// order they render in.
//
// Everything reads and writes through CompositorService's backend contract
// (BackendBase's outputs/refreshOutputs/setOutput*), never `niri msg` or
// `hyprctl` from here: the two compositors disagree about almost all of this
// — niri configures outputs over its own JSON socket and has no mirroring
// primitive at all, Hyprland goes through a `monitor` config keyword and
// does — and that disagreement belongs in the backends. `backend` is a null
// BackendBase when no compositor was detected, so "no compositor" needs no
// branch of its own here: it simply has no outputs.
//
// SAFETY: nothing in this file reconfigures an output at startup or on open.
// The panel's only unprompted compositor traffic is refreshOutputs(), a pure
// read; every setOutput* call below hangs off a real click, wheel or keypress.
Panel {
    id: root

    panelTitle: "DISPLAY"
    panelWidth: Theme.space.popupWidthDefault

    // Bound to the active backend directly rather than through a forwarding
    // pair on CompositorService: output configuration is the one half of the
    // contract with a single consumer, and CompositorService already exposes
    // `backend` as public readonly state for exactly this.
    readonly property var _backend: CompositorService.backend

    readonly property var _outputs: Outputs.sortOutputs(root._backend.outputs)
    readonly property var _mirrorPlan: Outputs.mirrorPlan(root._outputs, CompositorService.focusedOutputName)
    readonly property var _mirroring: Outputs.mirroredNames(root._outputs)
    readonly property bool _mirrorOn: root._mirroring.length > 0

    // The hero's own subject (M28 Task 5): the focused output's own name and
    // resolution — never a fabricated mode for an output with none to report.
    readonly property var _focusedOutput: Outputs.findOutput(root._outputs, CompositorService.focusedOutputName)

    // Keyboard cursor over the sorted output rows, then the brightness
    // device rows (PowerPanel's numeric _cursor idiom — this table is one
    // flat walk, so an index fits where NetworkPanel's split sections needed
    // a key). -1 is NetworkPanel's empty sentinel in numeric form: no cursor
    // painted until the pointer or a navigation key puts one somewhere, so
    // an untouched panel doesn't highlight its first row for no reason.
    property int _cursor: -1

    readonly property int _cursorCount: root._outputs.length + BrightnessService.devices.count

    on_OutputsChanged: if (root._cursor >= root._cursorCount) root._cursor = root._cursorCount - 1

    Connections {
        target: BrightnessService.devices
        function onCountChanged() {
            if (root._cursor >= root._cursorCount)
                root._cursor = root._cursorCount - 1;
        }
    }

    onIsOpenChanged: {
        if (!root.isOpen)
            return;
        root._cursor = -1;
        root._backend.refreshOutputs();
        BrightnessService.refreshDevices();
    }

    // Neither compositor pushes output changes: niri's event stream has no
    // output event at all (niri-ipc's `Event` enum), and Hyprland's monitor
    // events never mention the disabled outputs this panel exists to switch
    // back on. So an open panel re-reads on a timer, the same 5s cadence
    // omarchy's monitor panel uses. Read-only, and only while open.
    Timer {
        interval: 5000
        repeat: true
        running: root.isOpen
        onTriggered: root._backend.refreshOutputs()
    }

    function _toggleOutput(name) {
        if (!Outputs.canToggle(root._outputs, name))
            return;
        var row = Outputs.findOutput(root._outputs, name);
        root._backend.setOutputEnabled(name, !row.enabled);
    }

    function _setScale(name, scale) {
        root._backend.setOutputScale(name, scale);
    }

    function _cursorRow() {
        return (root._cursor >= 0 && root._cursor < root._outputs.length) ? root._outputs[root._cursor] : null;
    }

    function _stepScale(direction) {
        var row = root._cursorRow();
        if (!row || !row.enabled)
            return;
        root._setScale(row.name, Outputs.stepScale(row.scale, direction));
    }

    // The brightness half of the same combined cursor: indices from
    // _outputs.length up to _cursorCount name a BrightnessService device.
    function _cursorBrightnessId() {
        if (root._cursor < root._outputs.length || root._cursor >= root._cursorCount)
            return "";
        return BrightnessService.devices.get(root._cursor - root._outputs.length).deviceId;
    }

    function _stepBrightness(delta) {
        var id = root._cursorBrightnessId();
        if (id !== "")
            BrightnessService.stepDevicePercent(id, delta);
    }

    // MIRROR is one bounded action over the whole set, not a per-output
    // source picker: "show the same thing everywhere" is what the control
    // means, so on points every other enabled output at the plan's primary
    // and off clears every output currently mirroring anything.
    function _setMirror(enabled) {
        if (!root._backend.mirrorSupported)
            return;
        if (!enabled) {
            for (var i = 0; i < root._mirroring.length; i++)
                root._backend.setOutputMirror(root._mirroring[i], "");
            return;
        }
        if (!root._mirrorPlan.ok)
            return;
        for (var j = 0; j < root._mirrorPlan.targets.length; j++)
            root._backend.setOutputMirror(root._mirrorPlan.targets[j], root._mirrorPlan.primary);
    }

    // Panel.qml's shared keyboard-nav hook (M6 Task 7): Up/Down move the
    // cursor across outputs then brightness devices, Enter switches an
    // output row on or off, h/l step an output row's scale or a brightness
    // row's percent depending which the cursor is on.
    Connections {
        target: root

        function onKeyPressed(event) {
            if (!root.isOpen || root._cursorCount === 0)
                return;
            switch (event.key) {
            case Qt.Key_Up:
                // The very first Up/Down (_cursor still -1) clamps straight
                // to row 0 rather than stepping past it, so this already IS
                // the reveal-only press (M26 Task 8, upstream's CursorSurface
                // contract) — cursorActive just has to catch up to it.
                root.cursorActive = true;
                root._cursor = root._cursor <= 0 ? 0 : root._cursor - 1;
                event.accepted = true;
                return;
            case Qt.Key_Down:
                root.cursorActive = true;
                root._cursor = Math.min(root._cursorCount - 1, root._cursor + 1);
                event.accepted = true;
                return;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                var row = root._cursorRow();
                if (row)
                    root._toggleOutput(row.name);
                event.accepted = true;
                return;
            }
            // h/l act on whichever half of the cursor is live: a scale step
            // on an output row, a brightness step on a device row — the two
            // helpers below are no-ops outside their own half, so calling
            // both is exactly one of them acting.
            if (event.text === "h" || event.text === "H") {
                root._stepScale(-1);
                root._stepBrightness(-5);
                event.accepted = true;
            } else if (event.text === "l" || event.text === "L") {
                root._stepScale(1);
                root._stepBrightness(5);
                event.accepted = true;
            }
        }
    }

    Component {
        id: outputRow

        Cell {
            id: outCell
            required property var modelData
            required property int index
            width: parent.width
            selected: outCell.modelData.name === CompositorService.focusedOutputName
            hovered: root.cursorActive && root._cursor === outCell.index

            readonly property bool _canToggle: root._backend.outputConfigAvailable
                && Outputs.canToggle(root._outputs, outCell.modelData.name)
            readonly property string _identity: Outputs.describe(outCell.modelData)
            // Which card drives this output, e.g. "NVIDIA / DISCRETE". ""
            // on a single-GPU machine, or when the connector matches
            // nothing in GpuService.cards (M38 Task 9).
            readonly property string _cardLabel: Outputs.outputCardLabel(outCell.modelData.name, GpuService.cards)
            // The screen `display.outputPriority` resolves to
            // (MainOutputService), marked only where the answer can be
            // anything else: on a one-output session naming it MAIN says
            // nothing the list above doesn't already.
            readonly property string _mainLabel: (root._outputs.length > 1
                && MainOutputService.isMain(outCell.modelData.name)) ? "MAIN DISPLAY" : ""
            // The focused row's own resolution is already the hero's meta
            // line above (M28 Task 5); this row keeps scale/mirror only, so
            // the mode isn't printed twice.
            readonly property string _status: outCell.selected
                ? Outputs.statusLineNoMode(outCell.modelData)
                : Outputs.statusLine(outCell.modelData)
            // Same drop, completed: the focused row's own name is already
            // the hero's title above, so this row's identity line goes
            // blank rather than repeat it. The inversion (selected) is
            // already what marks this row as the hero's row.
            readonly property string _nameText: outCell.selected ? "" : outCell.modelData.name

            // Takes no buttons: the cell's own target sits under its content,
            // so every control in the Column below stays above it and keeps
            // its own hover, and this only follows the pointer to move the
            // shared keyboard cursor onto the row it is over.
            interactive: true
            acceptedButtons: Qt.NoButton
            onContainsPointerChanged: if (outCell.containsPointer) {
                root.cursorActive = true;
                root._cursor = outCell.index;
            }

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                Row {
                    width: parent.width
                    spacing: Theme.space.sm

                    Text {
                        width: parent.width - toggleLabel.width - parent.spacing
                        text: outCell._nameText
                        color: outCell.foreground
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.body
                    }

                    // Bare-label ink promotion (DESIGN.md §1.1's 2026-08-09
                    // amendment): no cell chrome, armed state promotes
                    // straight to accent instead of a fill/inversion. The
                    // last enabled output has no OFF to offer, so its resting
                    // ink stays dim rather than promoting on a control that
                    // would do nothing.
                    MetaLabel {
                        id: toggleLabel
                        text: outCell.modelData.enabled ? "ON" : "OFF"
                        // The focused output's own row is already a full-bleed
                        // accent fill (outCell.selected); accent ink on an
                        // accent ground is unreadable, so this label collapses
                        // to the row's own contrasting ink instead, matching
                        // Cell.dimForeground's single-band precedent.
                        color: outCell.selected
                            ? outCell.foreground
                            : (outCell.modelData.enabled && outCell._canToggle)
                                ? Theme.color.accent
                                : (toggleHover.containsMouse ? Theme.color.foreground : Theme.color.foregroundDim)

                        MouseArea {
                            id: toggleHover
                            anchors.fill: parent
                            enabled: outCell._canToggle
                            hoverEnabled: outCell._canToggle
                            cursorShape: outCell._canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onContainsMouseChanged: if (toggleHover.containsMouse) {
                                root.cursorActive = true;
                                root._cursor = outCell.index;
                            }
                            onClicked: root._toggleOutput(outCell.modelData.name)
                        }
                    }
                }

                // Color collapses to the row's own ink when selected, the
                // same single-band precedent the ON/OFF label above already
                // follows: `foregroundDim` on the focused row's accent fill
                // measures unreadable.
                MetaLabel {
                    width: parent.width
                    visible: outCell._status !== ""
                    text: outCell._status
                    color: outCell.selected ? outCell.foreground : Theme.color.foregroundDim
                    elide: Text.ElideRight
                }

                MetaLabel {
                    width: parent.width
                    visible: outCell._identity !== ""
                    text: outCell._identity
                    color: outCell.selected ? outCell.foreground : Theme.color.foregroundDim
                    elide: Text.ElideRight
                }

                MetaLabel {
                    width: parent.width
                    visible: outCell._cardLabel !== ""
                    text: outCell._cardLabel
                    color: outCell.selected ? outCell.foreground : Theme.color.foregroundDim
                    elide: Text.ElideRight
                }

                MetaLabel {
                    width: parent.width
                    visible: outCell._mainLabel !== ""
                    text: outCell._mainLabel
                    color: outCell.selected ? outCell.foreground : Theme.color.foregroundDim
                    elide: Text.ElideRight
                }

                Column {
                    width: parent.width
                    visible: outCell.modelData.enabled && root._backend.outputConfigAvailable
                    spacing: Theme.space.xxs

                    Row {
                        width: parent.width
                        spacing: Theme.space.sm

                        MetaLabel {
                            width: parent.width - scaleValue.width - parent.spacing
                            text: "SCALE"
                            color: outCell.selected ? outCell.foreground : Theme.color.foregroundDim
                        }

                        Text {
                            id: scaleValue
                            text: Outputs.formatScale(outCell.modelData.scale)
                            color: outCell.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize.caption
                        }
                    }

                    // Flat accent fill, no thumb, no gauge — the shell's one
                    // slider idiom. Press and wheel each commit exactly one
                    // value; there is deliberately no drag-to-scrub the way
                    // AudioPanel's volume track has one, because every step
                    // here is a real output reconfiguration and a drag would
                    // fire dozens of them across the pointer's travel.
                    DitherFill {
                        id: scaleTrack
                        width: parent.width
                        height: Theme.space.trackThickness

                        Rectangle {
                            width: parent.width * Outputs.fractionForScale(outCell.modelData.scale)
                            height: parent.height
                            color: Theme.color.accent
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => root._setScale(outCell.modelData.name, Outputs.scaleForFraction(mouse.x / scaleTrack.width))
                            onWheel: wheel => {
                                root._setScale(outCell.modelData.name, Outputs.stepScale(outCell.modelData.scale, wheel.angleDelta.y > 0 ? 1 : -1));
                                wheel.accepted = true;
                            }
                        }
                    }
                }
            }
        }
    }

    // The panel's own subject (M28 Task 5): the focused output's own name
    // and resolution — hidden entirely when nothing is focused, the same
    // honest-unavailable gate every other hero uses.
    PanelHero {
        visible: root._focusedOutput !== null
        width: parent.width
        glyph: "󰍹"
        title: root._focusedOutput ? root._focusedOutput.name : ""
        meta: root._focusedOutput ? Outputs.modeLabel(root._focusedOutput) : ""
    }

    // An empty list means two different things and only one of them licenses
    // NO OUTPUTS — see BackendBase's outputsState. A failed hyprctl/niri query
    // must not tell a session with two lit monitors it has no displays.
    Cell {
        visible: root._outputs.length === 0
        width: parent.width

        MetaLabel {
            text: {
                switch (root._backend.outputsState) {
                case "failed": return "CANNOT READ OUTPUTS";
                case "ok": return "NO OUTPUTS";
                default: return "LOADING";
                }
            }
        }
    }

    Cell {
        visible: root._outputs.length > 0
        width: parent.width

        MetaLabel { text: "OUTPUTS"; colon: true }
    }

    Repeater {
        model: root._outputs
        delegate: outputRow
    }

    Cell {
        width: parent.width

        MetaLabel { text: "BRIGHTNESS"; colon: true }
    }

    Cell {
        visible: BrightnessService.devices.count === 0
        width: parent.width

        MetaLabel { text: "NO BACKLIGHT" }
    }

    Component {
        id: brightnessRow

        Cell {
            id: brightnessCell
            required property int index
            required property string deviceId
            required property string label
            required property real percent
            width: parent.width
            hovered: root.cursorActive && root._cursor === (root._outputs.length + brightnessCell.index)

            // Same whole-row hover-to-cursor wiring as outputRow above: the
            // cell's own pointer layer tracks hover across the row, the
            // track's MouseArea below keeps its own press/wheel events.
            interactive: true
            acceptedButtons: Qt.NoButton
            onContainsPointerChanged: if (brightnessCell.containsPointer) {
                root.cursorActive = true;
                root._cursor = root._outputs.length + brightnessCell.index;
            }

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                Row {
                    width: parent.width
                    spacing: Theme.space.sm

                    Text {
                        width: parent.width - percentText.width - parent.spacing
                        text: brightnessCell.label
                        color: brightnessCell.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.body
                    }

                    Text {
                        id: percentText
                        text: brightnessCell.percent + "%"
                        color: brightnessCell.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.body
                    }
                }

                // Flat accent fill, no thumb — same idiom as the scale
                // track above and every other slider in the shell.
                DitherFill {
                    id: brightnessTrack
                    width: parent.width
                    height: Theme.space.trackThickness

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, brightnessCell.percent / 100))
                        height: parent.height
                        color: Theme.color.accent
                    }

                    MouseArea {
                        anchors.fill: parent
                        function _setFromX(x) {
                            BrightnessService.setDevicePercent(brightnessCell.deviceId, (x / brightnessTrack.width) * 100);
                        }
                        onPressed: mouse => _setFromX(mouse.x)
                        onPositionChanged: mouse => { if (pressed) _setFromX(mouse.x); }
                        onWheel: wheel => {
                            BrightnessService.stepDevicePercent(brightnessCell.deviceId, wheel.angleDelta.y > 0 ? 5 : -5);
                            wheel.accepted = true;
                        }
                    }
                }
            }
        }
    }

    Repeater {
        model: BrightnessService.devices
        delegate: brightnessRow
    }

    Cell {
        visible: root._outputs.length > 0
        width: parent.width

        MetaLabel { text: "MIRROR"; colon: true }
    }

    Cell {
        visible: root._outputs.length > 0 && !root._backend.mirrorSupported
        width: parent.width

        MetaLabel { text: "MIRROR UNSUPPORTED" }
    }

    Cell {
        visible: root._outputs.length > 0 && root._backend.mirrorSupported && !root._mirrorPlan.ok
        width: parent.width

        MetaLabel { text: "SINGLE DISPLAY" }
    }

    Cell {
        id: mirrorCell
        visible: root._outputs.length > 0 && root._backend.mirrorSupported && root._mirrorPlan.ok
        width: parent.width

        Row {
            width: parent.width
            spacing: Theme.space.sm

            Text {
                width: parent.width - mirrorLabel.width - parent.spacing
                // What the mirror is centred on: the live source while it is
                // on, the primary the plan would pick while it is off.
                text: root._mirrorOn ? Outputs.mirrorSource(root._outputs) : root._mirrorPlan.primary
                color: mirrorCell.foreground
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }

            // Bare-label ink promotion (DESIGN.md §1.1's 2026-08-09
            // amendment): no cell chrome, armed state promotes straight to
            // accent instead of a fill/inversion.
            MetaLabel {
                id: mirrorLabel
                text: root._mirrorOn ? "ON" : "OFF"
                color: root._mirrorOn
                    ? Theme.color.accent
                    : (mirrorHover.containsMouse ? Theme.color.foreground : Theme.color.foregroundDim)

                MouseArea {
                    id: mirrorHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._setMirror(!root._mirrorOn)
                }
            }
        }
    }
}

import QtQuick
import qs.Core
import qs.Components
import qs.Compositor
import qs.Services
import "../../Display/outputs.js" as Outputs

// Display panel (DESIGN.md §3 "Panel", spec "Panels", M17): a hero for the
// focused output, then `OUTPUTS (n)` as one row per connected output
// carrying the three things the owner asked for (on/off, scale, mirror),
// `BRIGHTNESS (n)` per backlight device, and the mirror control below them.
// Feature shape read off omarchy's monitor panel and reimplemented in this
// shell's own language.
//
// BRIGHTNESS (M33, owner reversal of the M16 call: "move the display things
// from battery to display, it makes no sense they were merged anyway") sits
// between OUTPUTS and MIRROR, one row per BrightnessService device sharing
// this panel's own cursor: a second keyboard cursor on the same panel would
// double-drive whichever row both happened to point at.
//
// Keyboard (spec "Keyboard model"): one flat cursor walks outputs, then
// backlight devices, then the mirror row, in the order they render. Enter
// switches an output on or off and flips the mirror; Left and Right step
// the scale on an output row and the percent on a brightness row (Panel's
// `cursorStepsHorizontally`), the same 5% the wheel over either track
// commits.
//
// The GPU annotation (M38 Task 9) names the card driving each connector,
// which is a hardware identity, so it renders in mono like the make/model
// line above it and is absent entirely on a single-card machine.
//
// Everything reads and writes through CompositorService's backend contract
// (BackendBase's outputs/refreshOutputs/setOutput*), never `hyprctl` from
// here: the two compositors disagree about almost all of this, and that
// disagreement belongs in the backends. `backend` is a null BackendBase when
// no compositor was detected, so "no compositor" needs no branch of its own:
// it simply has no outputs.
//
// SAFETY: nothing in this file reconfigures an output at startup or on open.
// The panel's only unprompted compositor traffic is refreshOutputs(), a pure
// read; every setOutput* call below hangs off a real click, wheel or
// keypress.
Panel {
    id: root

    panelIcon: "monitor"
    panelTitle: "Display"
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
    readonly property bool _mirrorActionable: root._outputs.length > 0
        && root._backend.mirrorSupported && root._mirrorPlan.ok

    // The hero's own subject (M28 Task 5): the focused output's own name and
    // resolution, never a fabricated mode for an output with none to report.
    readonly property var _focusedOutput: Outputs.findOutput(root._outputs, CompositorService.focusedOutputName)

    readonly property int _brightnessCount: BrightnessService.devices.count
    // The mirror row is the last cursor stop, and only while it can act on
    // anything.
    readonly property int _mirrorIndex: root._mirrorActionable
        ? root._outputs.length + root._brightnessCount
        : -1

    cursorCount: root._outputs.length + root._brightnessCount + (root._mirrorActionable ? 1 : 0)
    // Left/Right belong to the track on the cursor row, not to the list.
    cursorStepsHorizontally: true

    function _outputAt(index) {
        return (index >= 0 && index < root._outputs.length) ? root._outputs[index] : null;
    }

    function _brightnessIdAt(index) {
        var offset = index - root._outputs.length;
        if (offset < 0 || offset >= root._brightnessCount)
            return "";
        return BrightnessService.devices.get(offset).deviceId;
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

    onCursorActivated: index => {
        if (index === root._mirrorIndex) {
            root._setMirror(!root._mirrorOn);
            return;
        }
        var row = root._outputAt(index);
        if (row)
            root._toggleOutput(row.name);
    }

    onCursorStepped: (index, direction) => {
        var row = root._outputAt(index);
        if (row) {
            if (row.enabled)
                root._setScale(row.name, Outputs.stepScale(row.scale, direction));
            return;
        }
        var id = root._brightnessIdAt(index);
        if (id !== "")
            BrightnessService.stepDevicePercent(id, direction * 5);
    }

    onIsOpenChanged: {
        if (!root.isOpen)
            return;
        root.cursorIndex = 0;
        root._backend.refreshOutputs();
        BrightnessService.refreshDevices();
    }

    // The compositor pushes no output changes, and Hyprland's monitor
    // events never mention the disabled outputs this panel exists to switch
    // back on. So an open panel re-reads on a timer, the same 5s cadence
    // omarchy's monitor panel uses. Read-only, and only while open.
    Timer {
        interval: 5000
        repeat: true
        running: root.isOpen
        onTriggered: root._backend.refreshOutputs()
    }

    Component {
        id: outputRow

        Cell {
            id: outCell
            required property var modelData
            required property int index
            width: parent.width
            cursor: root.cursorActive && root.cursorIndex === outCell.index

            // The focused output is marked on its icon, not by filling the
            // row: `muted` and `accent` are the same zinc step in the dark
            // fallback, so a `selected` fill under this row's scale track
            // would swallow the track's own groove whole.
            readonly property bool _focused: outCell.modelData.name === CompositorService.focusedOutputName

            readonly property bool _canToggle: root._backend.outputConfigAvailable
                && Outputs.canToggle(root._outputs, outCell.modelData.name)
            readonly property bool _configurable: outCell.modelData.enabled && root._backend.outputConfigAvailable
            readonly property string _identity: Outputs.describe(outCell.modelData)
            readonly property string _mode: Outputs.modeLabel(outCell.modelData)
            // Which card drives this output, e.g. "NVIDIA / DISCRETE". Empty
            // on a single-GPU machine, or when the connector matches nothing
            // in GpuService.cards (M38 Task 9).
            readonly property string _cardLabel: Outputs.outputCardLabel(outCell.modelData.name, GpuService.cards)
            // The screen `display.outputPriority` resolves to
            // (MainOutputService), marked only where the answer can be
            // anything else: on a one-output session naming it MAIN says
            // nothing the list above doesn't already.
            readonly property bool _isMain: root._outputs.length > 1
                && MainOutputService.isMain(outCell.modelData.name)

            // Hover moves the shared cursor onto this row; the controls in
            // the column below sit above the cell's own pointer layer and
            // keep their own clicks.
            interactive: true
            acceptedButtons: Qt.NoButton
            onContainsPointerChanged: if (outCell.containsPointer) {
                root.cursorActive = true;
                root.cursorIndex = outCell.index;
            }

            Column {
                width: parent.width
                spacing: Theme.space.xs

                Item {
                    width: parent.width
                    height: Math.max(outName.implicitHeight, enableButton.height)

                    Icon {
                        id: outIcon
                        name: outCell.modelData.enabled ? "monitor" : "monitor-off"
                        size: Theme.fontSize.body
                        color: outCell._focused ? Theme.color.primary : outCell.foreground
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        id: outName
                        anchors.left: outIcon.right
                        anchors.leftMargin: Theme.space.iconGap
                        anchors.right: scaleValue.visible ? scaleValue.left : enableButton.left
                        anchors.rightMargin: Theme.space.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        text: outCell.modelData.name
                        color: outCell.foreground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                        elide: Text.ElideRight
                    }

                    Text {
                        id: scaleValue
                        anchors.right: enableButton.left
                        anchors.rightMargin: Theme.space.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        visible: outCell._configurable
                        text: Outputs.formatScale(outCell.modelData.scale)
                        color: outCell.dimForeground
                        font.family: Theme.fontFamilyMono
                        font.pixelSize: Theme.fontSize.bodySmall
                    }

                    Button {
                        id: enableButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        variant: outCell.modelData.enabled ? "default" : "outline"
                        text: outCell.modelData.enabled ? "On" : "Off"
                        enabled: outCell._canToggle
                        onClicked: root._toggleOutput(outCell.modelData.name)
                    }
                }

                SectionLabel {
                    visible: !outCell.modelData.enabled
                    text: "DISABLED"
                    color: outCell.dimForeground
                }

                SectionLabel {
                    visible: outCell.modelData.mirrorOf !== ""
                    text: "MIRRORS " + outCell.modelData.mirrorOf
                    color: outCell.dimForeground
                }

                SectionLabel {
                    visible: outCell._isMain
                    text: "MAIN DISPLAY"
                    color: outCell.dimForeground
                }

                // Mode, hardware identity and the card driving the connector
                // are all values, so they take the mono face (DESIGN.md §1
                // "Type") and each is absent rather than a placeholder when
                // the compositor reports nothing for it.
                Text {
                    width: parent.width
                    visible: outCell._mode !== ""
                    text: outCell._mode
                    color: outCell.dimForeground
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSize.bodySmall
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: outCell._identity !== ""
                    text: outCell._identity
                    color: outCell.dimForeground
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSize.bodySmall
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: outCell._cardLabel !== ""
                    text: outCell._cardLabel
                    color: outCell.dimForeground
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSize.bodySmall
                    elide: Text.ElideRight
                }

                // Press and wheel each commit exactly one value; there is
                // deliberately no drag-to-scrub the way AudioPanel's volume
                // track has one, because every step here is a real output
                // reconfiguration and a drag would fire dozens of them
                // across the pointer's travel.
                Track {
                    id: scaleTrack
                    width: parent.width
                    visible: outCell._configurable
                    value: Outputs.fractionForScale(outCell.modelData.scale)

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

    Component {
        id: brightnessRow

        Cell {
            id: brightnessCell
            required property int index
            required property string deviceId
            required property string label
            required property real percent
            width: parent.width
            cursor: root.cursorActive && root.cursorIndex === (root._outputs.length + brightnessCell.index)

            interactive: true
            acceptedButtons: Qt.NoButton
            onContainsPointerChanged: if (brightnessCell.containsPointer) {
                root.cursorActive = true;
                root.cursorIndex = root._outputs.length + brightnessCell.index;
            }

            Column {
                width: parent.width
                spacing: Theme.space.xs

                Item {
                    width: parent.width
                    height: brightnessLabel.implicitHeight

                    Icon {
                        id: brightnessIcon
                        name: "sun"
                        size: Theme.fontSize.body
                        color: brightnessCell.foreground
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        id: brightnessLabel
                        anchors.left: brightnessIcon.right
                        anchors.leftMargin: Theme.space.iconGap
                        anchors.right: brightnessPercent.left
                        anchors.rightMargin: Theme.space.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        text: brightnessCell.label
                        color: brightnessCell.foreground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                        elide: Text.ElideRight
                    }

                    Text {
                        id: brightnessPercent
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: brightnessCell.percent + "%"
                        color: brightnessCell.dimForeground
                        font.family: Theme.fontFamilyMono
                        font.pixelSize: Theme.fontSize.bodySmall
                    }
                }

                Track {
                    id: brightnessTrack
                    width: parent.width
                    value: brightnessCell.percent / 100

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
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

    // The panel's own subject (M28 Task 5): the focused output's own name and
    // resolution, hidden entirely when nothing is focused, the same
    // honest-unavailable gate every other hero uses.
    PanelHero {
        id: hero
        visible: root._focusedOutput !== null
        width: parent.width
        title: root._focusedOutput ? root._focusedOutput.name : ""
        meta: root._focusedOutput ? Outputs.modeLabel(root._focusedOutput) : ""
        metaMono: true

        leading: Component {
            Icon {
                name: "monitor"
                size: Theme.fontSize.heading
                color: hero.foreground
            }
        }
    }

    // An empty list means two different things and only one of them licenses
    // NO OUTPUTS, see BackendBase's outputsState. A failed hyprctl query must
    // not tell a session with two lit monitors it has no displays.
    Cell {
        visible: root._outputs.length === 0
        width: parent.width

        SectionLabel {
            text: {
                switch (root._backend.outputsState) {
                case "failed": return "CANNOT READ OUTPUTS";
                case "ok": return "NO OUTPUTS";
                default: return "LOADING";
                }
            }
        }
    }

    Column {
        width: parent.width
        visible: root._outputs.length > 0
        spacing: Theme.space.rowGap

        SectionLabel { text: "OUTPUTS"; count: root._outputs.length }

        Repeater {
            model: root._outputs
            delegate: outputRow
        }
    }

    Column {
        width: parent.width
        spacing: Theme.space.rowGap

        SectionLabel { text: "BRIGHTNESS"; count: root._brightnessCount }

        Cell {
            visible: root._brightnessCount === 0
            width: parent.width

            SectionLabel { text: "NO BACKLIGHT" }
        }

        Repeater {
            model: BrightnessService.devices
            delegate: brightnessRow
        }
    }

    Column {
        width: parent.width
        visible: root._outputs.length > 0
        spacing: Theme.space.rowGap

        SectionLabel { text: "MIRROR" }

        Cell {
            visible: !root._backend.mirrorSupported
            width: parent.width

            SectionLabel { text: "MIRROR UNSUPPORTED" }
        }

        Cell {
            visible: root._backend.mirrorSupported && !root._mirrorPlan.ok
            width: parent.width

            SectionLabel { text: "SINGLE DISPLAY" }
        }

        Cell {
            id: mirrorCell
            visible: root._mirrorActionable
            width: parent.width
            cursor: root.cursorActive && root._mirrorIndex >= 0 && root.cursorIndex === root._mirrorIndex

            interactive: true
            acceptedButtons: Qt.NoButton
            onContainsPointerChanged: if (mirrorCell.containsPointer && root._mirrorIndex >= 0) {
                root.cursorActive = true;
                root.cursorIndex = root._mirrorIndex;
            }

            Item {
                width: parent.width
                height: Math.max(mirrorSource.implicitHeight, mirrorButton.height)

                Icon {
                    id: mirrorIcon
                    name: "copy"
                    size: Theme.fontSize.body
                    color: mirrorCell.foreground
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                // What the mirror is centred on: the live source while it is
                // on, the primary the plan would pick while it is off. An
                // output name, so mono.
                Text {
                    id: mirrorSource
                    anchors.left: mirrorIcon.right
                    anchors.leftMargin: Theme.space.iconGap
                    anchors.right: mirrorButton.left
                    anchors.rightMargin: Theme.space.iconGap
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._mirrorOn ? Outputs.mirrorSource(root._outputs) : root._mirrorPlan.primary
                    color: mirrorCell.foreground
                    elide: Text.ElideRight
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSize.body
                }

                Button {
                    id: mirrorButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    variant: root._mirrorOn ? "default" : "outline"
                    text: root._mirrorOn ? "On" : "Off"
                    onClicked: root._setMirror(!root._mirrorOn)
                }
            }
        }
    }
}

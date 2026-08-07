import QtQuick
import qs.Core
import qs.Components
import qs.Compositor
import "../../Display/outputs.js" as Outputs

// Display panel (DESIGN.md §Panels, M17): a ledger of every connected output
// — one row each, the focused one inverted — carrying the three things the
// owner asked for, on/off, scale, and mirror. Feature shape read off
// omarchy's monitor panel (shell/plugins/panels/monitor/Panel.qml there:
// internalMonitor/externalMonitor/internalEnabled/mirrorEnabled/monitorScale/
// displays) and reimplemented in this shell's own language; its BRIGHTNESS
// slider is deliberately NOT here — the M16 plan declined DDC/external-monitor
// brightness for a laptop target, and BrightnessService already owns the
// backlight path from PowerPanel.
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

    // Bound to the active backend directly rather than through a forwarding
    // pair on CompositorService: output configuration is the one half of the
    // contract with a single consumer, and CompositorService already exposes
    // `backend` as public readonly state for exactly this.
    readonly property var _backend: CompositorService.backend

    readonly property var _outputs: Outputs.sortOutputs(root._backend.outputs)
    readonly property var _mirrorPlan: Outputs.mirrorPlan(root._outputs, CompositorService.focusedOutputName)
    readonly property var _mirroring: Outputs.mirroredNames(root._outputs)
    readonly property bool _mirrorOn: root._mirroring.length > 0

    // Keyboard cursor over the sorted output rows (PowerPanel's numeric
    // _cursor idiom — this table is one flat Repeater, so an index fits where
    // NetworkPanel's split sections needed a key). -1 is NetworkPanel's empty
    // sentinel in numeric form: no cursor painted until the pointer or a
    // navigation key puts one somewhere, so an untouched panel doesn't
    // highlight its first row for no reason.
    property int _cursor: -1

    on_OutputsChanged: if (root._cursor >= root._outputs.length) root._cursor = root._outputs.length - 1

    onIsOpenChanged: {
        if (!root.isOpen)
            return;
        root._cursor = -1;
        root._backend.refreshOutputs();
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
        return root._cursor >= 0 ? root._outputs[root._cursor] : null;
    }

    function _stepScale(direction) {
        var row = root._cursorRow();
        if (!row || !row.enabled)
            return;
        root._setScale(row.name, Outputs.stepScale(row.scale, direction));
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
    // cursor, Enter switches its output on or off, h/l step its scale — the
    // same h/l binding PowerPanel uses for the brightness it hovers.
    Connections {
        target: root

        function onKeyPressed(event) {
            if (!root.isOpen || root._outputs.length === 0)
                return;
            switch (event.key) {
            case Qt.Key_Up:
                root._cursor = root._cursor <= 0 ? 0 : root._cursor - 1;
                event.accepted = true;
                return;
            case Qt.Key_Down:
                root._cursor = Math.min(root._outputs.length - 1, root._cursor + 1);
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
            if (event.text === "h" || event.text === "H") {
                root._stepScale(-1);
                event.accepted = true;
            } else if (event.text === "l" || event.text === "L") {
                root._stepScale(1);
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
            hovered: rowMouse.containsMouse || toggleMouse.containsMouse || root._cursor === outCell.index

            readonly property bool _canToggle: root._backend.outputConfigAvailable
                && Outputs.canToggle(root._outputs, outCell.modelData.name)
            readonly property string _identity: Outputs.describe(outCell.modelData)
            readonly property string _status: Outputs.statusLine(outCell.modelData)

            // First child, so every control in the Column below sits above it
            // and keeps its own hover: this one only follows the pointer to
            // move the shared keyboard cursor onto the row it is over.
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onContainsMouseChanged: if (containsMouse) root._cursor = outCell.index
            }

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                Row {
                    width: parent.width
                    spacing: Theme.space.sm

                    Text {
                        width: parent.width - toggleCell.width - parent.spacing
                        text: outCell.modelData.name
                        color: outCell.foreground
                        elide: Text.ElideRight
                        font.family: Theme.font.family
                        font.pixelSize: Theme.fontSize.body
                    }

                    Cell {
                        id: toggleCell
                        width: implicitWidth
                        height: implicitHeight
                        // The last enabled output has no OFF to offer. It says
                        // so with the shell's own dim token rather than a
                        // fractional opacity: `selected` inverts this cell, so
                        // multiplying the whole thing by an opacity would drag
                        // its fill AND its background-colored label down
                        // together and land the pair below every other label on
                        // the panel for contrast. Nothing else in shell/ dims
                        // by opacity, and no Theme token defines one.
                        selected: outCell.modelData.enabled && outCell._canToggle

                        MetaLabel {
                            text: outCell.modelData.enabled ? "ON" : "OFF"
                            color: outCell._canToggle ? toggleCell.foreground : Theme.color.foregroundDim
                        }

                        MouseArea {
                            id: toggleMouse
                            anchors.fill: parent
                            enabled: outCell._canToggle
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._toggleOutput(outCell.modelData.name)
                        }
                    }
                }

                MetaLabel {
                    width: parent.width
                    visible: outCell._status !== ""
                    text: outCell._status
                    elide: Text.ElideRight
                }

                MetaLabel {
                    width: parent.width
                    visible: outCell._identity !== ""
                    text: outCell._identity
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
                        }

                        Text {
                            id: scaleValue
                            text: Outputs.formatScale(outCell.modelData.scale)
                            color: outCell.foreground
                            font.family: Theme.font.family
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

        MetaLabel { text: "OUTPUTS" }
    }

    Repeater {
        model: root._outputs
        delegate: outputRow
    }

    Cell {
        visible: root._outputs.length > 0
        width: parent.width

        MetaLabel { text: "MIRROR" }
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
                width: parent.width - mirrorToggle.width - parent.spacing
                // What the mirror is centred on: the live source while it is
                // on, the primary the plan would pick while it is off.
                text: root._mirrorOn ? Outputs.mirrorSource(root._outputs) : root._mirrorPlan.primary
                color: mirrorCell.foreground
                elide: Text.ElideRight
                font.family: Theme.font.family
                font.pixelSize: Theme.fontSize.body
            }

            Cell {
                id: mirrorToggle
                width: implicitWidth
                height: implicitHeight
                selected: root._mirrorOn

                MetaLabel {
                    text: root._mirrorOn ? "ON" : "OFF"
                    color: mirrorToggle.foreground
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._setMirror(!root._mirrorOn)
                }
            }
        }
    }
}

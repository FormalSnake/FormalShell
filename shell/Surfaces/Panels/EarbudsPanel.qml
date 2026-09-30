import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../Earbuds/model.js" as Model

// Earbuds panel (DESIGN.md §3 "Panel", spec
// docs/superpowers/specs/2026-09-30-m77-earbuds.md): the popout behind
// EarbudsWidget's cell, drawn from EarbudsService.active alone. It never
// branches on vendor: a `choice` control is a ButtonGroup, a `toggle` a
// Switch row, a `range` a Track, each under its control's `section`, in the
// order the adapter listed them. Holds the service for as long as it is
// open, so a host with no earbuds never pays for a panel nobody opens.
//
// Honest states first: no backend source at all renders one dim "No
// daemon" row; a source with no device it knows of renders "No earbuds
// connected". With more than one device a choice of them heads the panel.
//
// Keyboard (spec "Keyboard model"): one cursor walks the device choice and
// then every control in visual order. On a group Left and Right move the
// ring inside it, across the rows of a wrapped one in reading order, and
// Enter presses the button under it; on a range they
// step by the control's `step`, the same move the track's wheel makes. The
// cursor and each group's ring are keyed by control key rather than by
// index (AudioPanel's idiom): a control that appears mid-session must not
// slide the highlight onto a different one.
Panel {
    id: root

    panelIcon: "headphones"
    panelTitle: "Earbuds"
    panelWidth: Theme.space.popupWidthWide

    readonly property string _deviceKey: "__device"

    readonly property var _dev: EarbudsService.active
    readonly property var _devices: EarbudsService.devices
    readonly property var _batteryRows: Model.batteryRows(root._dev)
    readonly property var _sections: Model.sections(root._dev)
    readonly property bool _noDaemon: !EarbudsService.available
    readonly property bool _noDevice: !root._noDaemon && !root._dev
    readonly property bool _pickerVisible: root._devices.length > 1

    readonly property var _deviceOptions: root._devices.map(d => ({ label: d.name, value: d.key }))
    readonly property int _activeDeviceIndex: {
        for (var i = 0; i < root._devices.length; i++)
            if (root._dev && root._devices[i].key === root._dev.key)
                return i;
        return -1;
    }

    // A stand-in control for the device choice, so it walks, rings and
    // presses through the same code as every other group.
    readonly property var _deviceControl: ({
        key: root._deviceKey,
        kind: "choice",
        value: root._dev ? root._dev.key : null,
        options: root._deviceOptions
    })

    readonly property var _cursorEntries: {
        var out = [];
        if (root._pickerVisible)
            out.push(root._deviceControl);
        root._sections.forEach(s => s.controls.forEach(c => out.push(c)));
        return out;
    }

    property string _cursorKey: ""

    // Control key -> the ring's position in that group. Absent until the
    // ring first moves, and then a group's ring sits on its selected option.
    property var _rings: ({})

    function _ringOf(ctl) {
        var at = root._rings[ctl.key];
        if (at !== undefined && at < ctl.options.length)
            return at;
        return Math.max(0, Model.optionIndex(ctl));
    }

    function _setRing(key, index) {
        var next = Object.assign({}, root._rings);
        next[key] = index;
        root._rings = next;
    }

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

    function _set(ctl, value) {
        if (ctl.key === root._deviceKey)
            EarbudsService.select(value);
        else
            EarbudsService.set(ctl.key, value);
    }

    // Groups are controlled: a press writes the value and moves only the
    // ring, the selection follows once the device reports its new state.
    function _press(ctl, index) {
        if (index < 0 || index >= ctl.options.length)
            return;
        root._setRing(ctl.key, index);
        if (ctl.options[index].value !== ctl.value)
            root._set(ctl, ctl.options[index].value);
    }

    function _stepRange(ctl, direction) {
        root._set(ctl, ctl.value + direction * ctl.step);
    }

    cursorCount: root._cursorEntries.length
    // Left/Right belongs to whatever the cursor sits on, a group's buttons
    // or a range, not to the list: a single column already walks with
    // Up/Down.
    cursorStepsHorizontally: true

    onCursorIndexChanged: root._cursorKey = root._keyAt(root.cursorIndex)

    on_CursorEntriesChanged: {
        var index = root._indexForKey(root._cursorKey);
        if (index >= 0 && index !== root.cursorIndex)
            root.cursorIndex = index;
    }

    onCursorActivated: index => {
        var ctl = root._entryAt(index);
        if (!ctl)
            return;
        if (ctl.kind === "choice")
            root._press(ctl, root._ringOf(ctl));
        else if (ctl.kind === "toggle")
            root._set(ctl, !ctl.value);
    }

    onCursorStepped: (index, direction) => {
        var ctl = root._entryAt(index);
        if (!ctl)
            return;
        if (ctl.kind === "choice")
            root._setRing(ctl.key, Math.max(0, Math.min(ctl.options.length - 1, root._ringOf(ctl) + direction)));
        else if (ctl.kind === "range")
            root._stepRange(ctl, direction);
    }

    onIsOpenChanged: {
        if (root.isOpen) {
            // Each ring starts on what is already selected, so the
            // reveal-only first keypress shows it where the eye is.
            root._rings = ({});
            root.cursorIndex = 0;
            root.cursorSection = 0;
            root._cursorKey = root._keyAt(0);
            EarbudsService.acquire();
        } else {
            root._cursorKey = "";
            EarbudsService.release();
        }
    }

    SectionLabel {
        visible: root._noDaemon
        leftPadding: Theme.space.controlPaddingX
        text: "No daemon"
    }

    SectionLabel {
        visible: root._noDevice
        leftPadding: Theme.space.controlPaddingX
        text: "No earbuds connected"
    }

    Component {
        id: choiceGroup

        ButtonGroup {
            id: group
            property var ctl: null
            width: parent ? parent.width : 0
            // Six-option modes and presets do not fit one row at this width
            // with every label whole.
            wrap: true
            options: ctl ? ctl.options.map(o => ({ icon: o.icon || "", label: o.label, value: o.value, active: o.value === ctl.value })) : []
            index: Model.optionIndex(ctl)
            cursorIndex: ctl ? root._ringOf(ctl) : 0
            cursor: !!ctl && root.cursorActive && root._cursorKey === ctl.key
            onChanged: index => root._press(group.ctl, index)
            onHovered: (index, isHovered) => {
                if (!isHovered)
                    return;
                root._pointAt(group.ctl.key);
                root._setRing(group.ctl.key, index);
            }
        }
    }

    Column {
        width: parent.width
        visible: root._pickerVisible
        spacing: Theme.space.rowGap

        SectionLabel { leftPadding: Theme.space.controlPaddingX; text: "Device" }

        Loader {
            width: parent.width
            sourceComponent: choiceGroup
            onLoaded: item.ctl = Qt.binding(() => root._deviceControl)
        }
    }

    PanelHero {
        id: deviceHero
        visible: !!root._dev
        width: parent.width
        title: root._dev ? root._dev.name : ""
        meta: root._dev ? root._dev.stateLine : ""

        leading: Component {
            Icon {
                name: "headphones"
                size: Theme.fontSize.heading
                color: deviceHero.foreground
            }
        }
    }

    Column {
        width: parent.width
        visible: root._batteryRows.length > 0
        spacing: Theme.space.rowGap

        SectionLabel { leftPadding: Theme.space.controlPaddingX; text: "Battery" }

        // A borderless row leaves no box for a gap to sit between, so the rows
        // in a section abut and only `sectionGap` separates the sections.
        Column {
            width: parent.width
            spacing: 0

            // Counted rather than handed the array, so a level ticking
            // rebinds the rows in place instead of rebuilding them.
            Repeater {
                model: root._batteryRows.length

                Cell {
                    id: battCell
                    required property int index
                    readonly property var row: root._batteryRows[battCell.index] || ({ label: "", level: 0, hint: "" })
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
                                text: battCell.row.label
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
                                    visible: battCell.row.hint !== ""
                                    text: battCell.row.hint
                                    color: battCell.dimForeground
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: battCell.row.level + "%"
                                    color: battCell.foreground
                                    font.family: Theme.fontFamilyMono
                                    font.pixelSize: Theme.fontSize.body
                                    font.weight: Theme.weight.medium
                                }
                            }
                        }

                        Track {
                            width: parent.width
                            value: battCell.row.level / 100
                        }
                    }
                }
            }
        }
    }

    Repeater {
        model: root._sections.length

        Column {
            id: sectionColumn
            required property int index
            readonly property var section: root._sections[sectionColumn.index] || ({ section: "", controls: [] })
            width: parent.width
            spacing: Theme.space.rowGap

            SectionLabel { leftPadding: Theme.space.controlPaddingX; text: sectionColumn.section.section }

            // Rows abut the way borderless rows do everywhere else; a group
            // is a boxed control, so it keeps `rowGap` from its neighbours.
            Column {
                width: parent.width
                spacing: 0

                Repeater {
                    model: sectionColumn.section.controls.length

                    Item {
                        id: controlSlot
                        required property int index
                        readonly property var ctl: sectionColumn.section.controls[controlSlot.index] || null
                        readonly property var _prev: controlSlot.index > 0 ? sectionColumn.section.controls[controlSlot.index - 1] : null
                        readonly property real _gap: controlSlot._prev && controlSlot.ctl
                            && (controlSlot._prev.kind === "choice" || controlSlot.ctl.kind === "choice") ? Theme.space.rowGap : 0
                        width: parent.width
                        height: controlSlot._gap + controlLoader.height

                        Loader {
                            id: controlLoader
                            y: controlSlot._gap
                            width: parent.width
                            sourceComponent: !controlSlot.ctl ? null
                                : controlSlot.ctl.kind === "choice" ? choiceGroup
                                : controlSlot.ctl.kind === "toggle" ? toggleRow
                                : controlSlot.ctl.kind === "range" ? rangeRow
                                : null
                            onLoaded: item.ctl = Qt.binding(() => controlSlot.ctl)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: toggleRow

        Cell {
            id: toggleCell
            property var ctl: null
            width: parent ? parent.width : 0
            ghost: true
            cursor: !!ctl && root.cursorActive && root._cursorKey === ctl.key
            interactive: true
            onContainsPointerChanged: if (toggleCell.containsPointer) root._pointAt(toggleCell.ctl.key)
            onClicked: root._set(toggleCell.ctl, !toggleCell.ctl.value)

            Item {
                width: parent.width
                height: Math.max(toggleColumn.implicitHeight, toggleSwitch.height)

                Column {
                    id: toggleColumn
                    anchors.left: parent.left
                    anchors.right: toggleSwitch.left
                    anchors.rightMargin: Theme.space.iconGap
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space.xxs

                    Text {
                        width: parent.width
                        text: toggleCell.ctl ? toggleCell.ctl.label : ""
                        color: toggleCell.foreground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: toggleCell.ctl ? toggleCell.ctl.hint : ""
                        color: toggleCell.dimForeground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.bodySmall
                        elide: Text.ElideRight
                    }
                }

                // An on/off state is a `Switch` (DESIGN.md §2), never a
                // button whose label is the state. Enter on the row writes
                // the same value, so keyboard and pointer say one thing.
                Switch {
                    id: toggleSwitch
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: toggleCell.ctl ? toggleCell.ctl.value === true : false
                    onToggled: root._set(toggleCell.ctl, !toggleCell.ctl.value)
                }
            }
        }
    }

    Component {
        id: rangeRow

        Cell {
            id: rangeCell
            property var ctl: null
            width: parent ? parent.width : 0
            ghost: true
            cursor: !!ctl && root.cursorActive && root._cursorKey === ctl.key
            interactive: true
            acceptedButtons: Qt.NoButton
            onContainsPointerChanged: if (rangeCell.containsPointer) root._pointAt(rangeCell.ctl.key)

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                Item {
                    width: parent.width
                    height: Math.max(rangeLabel.implicitHeight, rangeValue.implicitHeight)

                    Text {
                        id: rangeLabel
                        anchors.left: parent.left
                        anchors.right: rangeValue.left
                        anchors.rightMargin: Theme.space.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        text: rangeCell.ctl ? rangeCell.ctl.label : ""
                        color: rangeCell.foreground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                        elide: Text.ElideRight
                    }

                    Text {
                        id: rangeValue
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: Model.rangeText(rangeCell.ctl)
                        color: rangeCell.foreground
                        font.family: Theme.fontFamilyMono
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                    }
                }

                Track {
                    id: rangeTrack
                    width: parent.width
                    value: Model.rangeFraction(rangeCell.ctl)

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function _setFromX(x) {
                            var c = rangeCell.ctl;
                            root._set(c, c.min + (x / rangeTrack.width) * (c.max - c.min));
                        }
                        onPressed: mouse => _setFromX(mouse.x)
                        onPositionChanged: mouse => { if (pressed) _setFromX(mouse.x); }
                        onWheel: wheel => {
                            root._stepRange(rangeCell.ctl, wheel.angleDelta.y > 0 ? 1 : -1);
                            wheel.accepted = true;
                        }
                    }
                }
            }
        }
    }
}

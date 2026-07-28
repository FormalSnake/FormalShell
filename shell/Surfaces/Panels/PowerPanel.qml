import QtQuick
import Quickshell.Services.UPower
import qs.Core
import qs.Components

// Power panel (DESIGN.md §Panels, spec §2, M6 Task 7): a battery/AC state
// row (no header — mirrors BluetoothPanel's headerless adapter row, since
// there's only ever one), then a keyboard-navigable power-profile picker
// under a PROFILE header, the active profile inverted. Bound directly to
// Quickshell.Services.UPower, same as AudioPanel binds Pipewire directly.
// The test VM's QEMU aarch64 "virt" machine has no battery at all —
// UPower.displayDevice.isLaptopBattery is then false and the panel renders
// the honest "AC POWER" cell instead of a lying 0%, mirroring Bluetooth's
// "NO ADAPTER" state. The charging pulse (DESIGN.md rule 9's breathing-
// opacity idiom for in-progress states) runs on the status row only while
// UPowerDeviceState.Charging is the live state.
Panel {
    id: root

    panelTitle: "POWER"

    readonly property var _device: UPower.displayDevice
    readonly property bool _hasBattery: root._device ? root._device.isLaptopBattery : false
    readonly property bool _charging: root._hasBattery && root._device.state === UPowerDeviceState.Charging
    readonly property int _percent: root._hasBattery ? Math.round(root._device.percentage) : 0

    // Fixed order matching the PowerProfile enum, so `_profiles[i] === i` —
    // PowerProfilesQml exposes no enumerable "available profiles" list, only
    // `hasPerformanceProfile`; a rejected Performance write just leaves the
    // live ActiveProfile DBus property (and this binding) unchanged, which
    // is the honest self-correcting behaviour rather than something this
    // panel needs to gate by hand.
    readonly property var _profiles: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]

    // Keyboard cursor (Up/Down), independent of the active profile —
    // rendered via Cell's `hovered` state so it reads as "pointed at" rather
    // than "selected" (that inversion stays reserved for the real active
    // profile). Reset to the active profile every time the panel opens.
    property int _cursor: 0
    onIsOpenChanged: if (root.isOpen) root._cursor = Math.max(0, root._profiles.indexOf(PowerProfiles.profile))

    function _applyProfile(index) {
        if (index < 0 || index >= root._profiles.length)
            return;
        root._cursor = index;
        PowerProfiles.profile = root._profiles[index];
    }

    // Panel.qml's shared keyboard-nav hook (M6 Task 7): Up/Down move the
    // cursor, Enter/Return applies it. Escape keeps closing the panel as
    // normal — Panel.qml dispatches that separately regardless of whether
    // this handler accepts the event.
    Connections {
        target: root

        function onKeyPressed(event) {
            if (!root.isOpen)
                return;
            switch (event.key) {
            case Qt.Key_Up:
                root._cursor = Math.max(0, root._cursor - 1);
                event.accepted = true;
                break;
            case Qt.Key_Down:
                root._cursor = Math.min(root._profiles.length - 1, root._cursor + 1);
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root._applyProfile(root._cursor);
                event.accepted = true;
                break;
            }
        }
    }

    Cell {
        id: statusCell
        visible: root._hasBattery
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.spacing.xs

            Text {
                id: statusText
                text: root._percent + "%  " + UPowerDeviceState.toString(root._device ? root._device.state : UPowerDeviceState.Unknown)
                color: statusCell.foreground
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body

                SequentialAnimation on opacity {
                    running: root._charging
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.4; duration: 900; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                }
            }

            // Flat accent fill, no thumb, no radius — same idiom as
            // AudioPanel's volume slider and CalendarPanel's year-progress
            // bar, read-only here (no MouseArea; the level isn't settable).
            Rectangle {
                width: parent.width
                height: 6
                color: Theme.color.rule

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root._percent / 100))
                    height: parent.height
                    color: Theme.color.accent
                }
            }
        }
    }

    Cell {
        visible: !root._hasBattery
        width: parent.width

        MetaLabel { text: "AC POWER" }
    }

    Cell {
        width: parent.width

        MetaLabel { text: "PROFILE" }
    }

    Component {
        id: profileRow

        Cell {
            id: profileCell
            required property int index
            required property var modelData
            width: parent.width
            selected: profileCell.modelData === PowerProfiles.profile
            hovered: profileCell.index === root._cursor

            Text {
                text: PowerProfile.toString(profileCell.modelData).toUpperCase()
                color: profileCell.foreground
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root._applyProfile(profileCell.index)
            }
        }
    }

    Repeater {
        model: root._profiles
        delegate: profileRow
    }
}

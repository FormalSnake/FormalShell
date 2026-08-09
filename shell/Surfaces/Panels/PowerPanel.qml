import QtQuick
import Quickshell.Services.UPower
import qs.Core
import qs.Components
import qs.Services
import qs.Notifications
import "../../Power/model.js" as Power

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
//
// M16 Task 5: this is the shell's one instance of PowerPanel (shell.qml
// wires the same `powerPanelInstance` into every screen's Bar) — the
// natural, already-live home for the low-battery watcher below, since a
// per-screen widget (Battery.qml) would otherwise fire the same warning
// once per monitor. `_percent`/`_charging` are real property bindings
// that update regardless of whether the panel is open, so the watcher
// runs continuously in the background exactly like the rest of this
// panel's state already does.
Panel {
    id: root

    panelTitle: "POWER"

    readonly property var _device: UPower.displayDevice
    readonly property bool _hasBattery: root._device ? root._device.isLaptopBattery : false
    readonly property bool _charging: root._hasBattery && root._device.state === UPowerDeviceState.Charging
    readonly property int _percent: root._hasBattery ? Math.round(root._device.percentage * 100) : 0
    readonly property real _timeToEmpty: root._hasBattery ? root._device.timeToEmpty : 0
    readonly property real _timeToFull: root._hasBattery ? root._device.timeToFull : 0
    readonly property real _changeRate: root._hasBattery ? root._device.changeRate : 0

    // M16 Task 11 (owner-requested, gated subtle): the glanceable phrase
    // set the status line rotates through — state first, then whichever
    // real fields the static rows below already render, same skip-if-
    // absent rule (never a "--", never a phrase for a field that isn't
    // reporting). A set with only one phrase (no time-to-X, no rate) never
    // rotates; the primary phrase is always index 0, so a closed/reopened
    // panel or a disabled-motion session both show exactly today's line.
    readonly property var _phrases: {
        if (!root._hasBattery)
            return [];
        var list = [root._percent + "%  " + UPowerDeviceState.toString(root._device.state).toUpperCase()];
        if (root._charging && root._timeToFull > 0)
            list.push("TIME TO FULL " + Power.formatDuration(root._timeToFull));
        if (!root._charging && root._timeToEmpty > 0)
            list.push("TIME TO EMPTY " + Power.formatDuration(root._timeToEmpty));
        if (root._changeRate !== 0)
            list.push("RATE " + Power.formatRate(root._changeRate));
        return list;
    }
    readonly property bool _rotating: root._hasBattery
        && (root._device.state === UPowerDeviceState.Charging || root._device.state === UPowerDeviceState.Discharging)
        && root._phrases.length > 1
    property int _phraseIndex: 0

    // Battery info dedup (owner: duplicate fields while discharging) —
    // Power.staticFieldsVisible's own header comment has the full rule.
    readonly property bool _staticFieldsVisible: Power.staticFieldsVisible(Theme.motionEnabled, root._rotating)

    // Hysteresis state for Power/model.js's warnEvent() — persisted here
    // across calls, never reset except by the model's own re-arm-on-charge
    // rule. See model.js's own header comment for the full behavior.
    readonly property real _warnPercentPref: Config.get("battery.warnPercent", 10)
    readonly property real _criticalPercentPref: Config.get("battery.criticalPercent", 5)
    property var _batteryFired: Power.initialFired()
    property var _lastBatteryPercent: null

    // The watcher's charging input is "anything that isn't actively
    // draining" (Charging/FullyCharged/PendingCharge re-arm), not the
    // pulse's narrow state === Charging — a battery sitting at 100% on AC
    // reports FullyCharged, and treating that as "discharging" would let
    // thresholds fire on it.
    readonly property bool _draining: root._hasBattery
        && (root._device.state === UPowerDeviceState.Discharging
            || root._device.state === UPowerDeviceState.PendingDischarge
            || root._device.state === UPowerDeviceState.Empty)

    function _checkBatteryThresholds() {
        if (!root._hasBattery)
            return;
        // Unknown means UPower's properties haven't populated yet (fresh
        // shell start): percentage can still read 0 here, and evaluating
        // that fired a false CRITICAL BATTERY at 100% on the e1504g
        // (2026-08-03). Skip WITHOUT recording _lastBatteryPercent, so the
        // first meaningful reading still gets the boot-below-threshold
        // rule against a null prev instead of a bogus notRising guard.
        if (root._device.state === UPowerDeviceState.Unknown)
            return;
        var result = Power.warnEvent(root._lastBatteryPercent, root._percent, !root._draining, root._batteryFired, root._warnPercentPref, root._criticalPercentPref);
        root._lastBatteryPercent = root._percent;
        root._batteryFired = result.fired;
        if (result.event === "warn")
            NotificationService.notify("LOW BATTERY", root._percent + "% REMAINING");
        else if (result.event === "critical")
            NotificationService.notify("CRITICAL BATTERY", root._percent + "% REMAINING", 2);
    }

    // Component.onCompleted covers a boot that starts already below a
    // threshold, which never generates a "changed" signal of its own —
    // the on_*Changed handlers below cover every real transition after
    // that (UPower keeps updating percentage/state independently of
    // whether this panel is open).
    Component.onCompleted: root._checkBatteryThresholds()
    on_PercentChanged: root._checkBatteryThresholds()
    on_ChargingChanged: root._checkBatteryThresholds()
    on_HasBatteryChanged: root._checkBatteryThresholds()
    on_DrainingChanged: root._checkBatteryThresholds()

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
    onIsOpenChanged: {
        if (root.isOpen) {
            root._cursor = Math.max(0, root._profiles.indexOf(PowerProfiles.profile));
            root._phraseIndex = 0;
            BrightnessService.refreshDevices();
        }
    }

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
            if (event.text === "h" || event.text === "H") {
                if (root._brightnessHoverId !== "")
                    BrightnessService.stepDevicePercent(root._brightnessHoverId, -5);
                event.accepted = true;
            } else if (event.text === "l" || event.text === "L") {
                if (root._brightnessHoverId !== "")
                    BrightnessService.stepDevicePercent(root._brightnessHoverId, 5);
                event.accepted = true;
            }
        }
    }

    Cell {
        id: statusCell
        visible: root._hasBattery
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.space.xxs

            // M16 Task 11: the phrase swap fades `statusTextWrap`'s opacity,
            // never `statusText`'s own — that one already carries the
            // charging breathing pulse below, and two animations writing
            // the same property would fight. Wrapping keeps them
            // independent: total rendered opacity is just the product of
            // both, so a swap mid-breath still reads as one organism.
            Item {
                id: statusTextWrap
                width: statusText.implicitWidth
                height: statusText.implicitHeight

                Text {
                    id: statusText
                    text: root._phrases.length > 0 ? root._phrases[root._phraseIndex % root._phrases.length] : ""
                    color: statusCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body

                    // Gated on root.isOpen too (M16 Task 12): this panel's
                    // content is instantiated once for the shell's whole
                    // lifetime (Panel.qml never destroys it on close, only
                    // hides the window), so an unqualified `running:
                    // root._charging` kept animating a fully hidden window
                    // for as long as the laptop stayed on AC.
                    SequentialAnimation on opacity {
                        running: root._charging && root.isOpen
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                        NumberAnimation { to: 1.0; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                    }
                }
            }

            // Advances `_phraseIndex` every `Theme.motion.rotatePeriod`
            // while the panel is open, motion is enabled, and there's more
            // than one real phrase to show — closing the panel, disabling
            // motion, or losing the rotating state all just stop new
            // triggers; the in-flight fade (if any) still runs to
            // completion on its own since nothing else writes
            // `statusTextWrap.opacity`.
            Timer {
                id: phraseTimer
                interval: Theme.motion.rotatePeriod
                running: root.isOpen && Theme.motionEnabled && root._rotating
                repeat: true
                triggeredOnStart: false
                onTriggered: phraseFade.restart()
            }

            SequentialAnimation {
                id: phraseFade
                PropertyAnimation { target: statusTextWrap; property: "opacity"; to: 0.0; duration: Theme.motion.standard; easing.type: Theme.motion.easing }
                ScriptAction { script: root._phraseIndex = (root._phraseIndex + 1) % Math.max(1, root._phrases.length) }
                PropertyAnimation { target: statusTextWrap; property: "opacity"; to: 1.0; duration: Theme.motion.standard; easing.type: Theme.motion.easing }
            }

            // Flat accent fill, no thumb, no radius — same idiom as
            // AudioPanel's volume slider and CalendarPanel's year-progress
            // bar, read-only here (no MouseArea; the level isn't settable).
            DitherFill {
                width: parent.width
                height: Theme.space.trackThickness

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root._percent / 100))
                    height: parent.height
                    color: Theme.color.accent
                }
            }

            // Static ports of the hero-rotation content (M16 Task 5):
            // dim meta rows, one per UPower field that's actually
            // reporting something — timeToFull is 0 while discharging
            // and timeToEmpty is 0 while charging (the pinned quickshell
            // source's own contract), so at most one of the two is ever
            // visible; changeRate is 0 when UPower simply has no reading
            // yet. Nothing renders in place of an absent value — no
            // "--", no rotation, no timer (Task 11's job). Gated on
            // `_staticFieldsVisible` (dedup fix, owner-reported): while the
            // status line above is actually rotating through these same
            // fields, showing them here too doubled the information: the
            // rotating line owns them, and these rows only render once it
            // isn't (motion disabled, or nothing to rotate through).
            MetaLabel {
                visible: root._staticFieldsVisible && root._charging && root._timeToFull > 0
                text: "TIME TO FULL " + Power.formatDuration(root._timeToFull)
            }

            MetaLabel {
                visible: root._staticFieldsVisible && !root._charging && root._timeToEmpty > 0
                text: "TIME TO EMPTY " + Power.formatDuration(root._timeToEmpty)
            }

            MetaLabel {
                visible: root._staticFieldsVisible && root._changeRate !== 0
                text: "RATE " + Power.formatRate(root._changeRate)
            }
        }
    }

    Cell {
        visible: !root._hasBattery
        width: parent.width

        MetaLabel { text: "AC POWER"; colon: true }
    }

    Cell {
        visible: BrightnessService.devices.count > 0
        width: parent.width

        MetaLabel { text: "DISPLAY"; colon: true }
    }

    Cell {
        visible: BrightnessService.devices.count === 0
        width: parent.width

        MetaLabel { text: "NO BACKLIGHT" }
    }

    // Mouse-hover cursor for the brightness rows below, independent of
    // the PROFILE section's keyboard `_cursor` — wheel is already
    // mouse-position-driven (like every other flat-track slider in the
    // shell), so pairing h/l with hover instead of folding brightness
    // into the arrow-key cursor keeps both inputs consistent with each
    // other without touching PROFILE's existing, working Up/Down system.
    property string _brightnessHoverId: ""

    Component {
        id: brightnessRow

        Cell {
            id: brightnessCell
            required property string deviceId
            required property string label
            required property real percent
            width: parent.width
            hovered: root._brightnessHoverId === brightnessCell.deviceId

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

                // Flat accent fill, no thumb — same idiom as the battery
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
                        hoverEnabled: true
                        onEntered: root._brightnessHoverId = brightnessCell.deviceId
                        onExited: if (root._brightnessHoverId === brightnessCell.deviceId) root._brightnessHoverId = ""
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
        width: parent.width

        MetaLabel { text: "PROFILE"; colon: true }
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

            ActionLabel {
                text: PowerProfile.toString(profileCell.modelData)
                color: profileCell.foreground
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

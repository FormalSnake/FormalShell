import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Core
import qs.Components
import qs.Notifications
import "../../Power/model.js" as Power

// Power panel (DESIGN.md §3 "Panel", spec "Panels"): a hero for the battery
// (state icon, "Battery", the state word, the percent as the display-sized
// readout and the charge level as the rail), a stats ledger of four
// label-and-mono-value cells, then the power-profile rows with the active
// one `selected`. Enter applies the profile under the cursor. Bound directly
// to Quickshell.Services.UPower, same as AudioPanel binds Pipewire directly.
// The test VM's QEMU aarch64 "virt" machine has no battery at all:
// UPower.displayDevice.isLaptopBattery is then false and the panel renders
// the honest "AC POWER" row instead of a lying 0%, mirroring Bluetooth's
// "NO ADAPTER" state.
//
// The charging pulse is DESIGN.md §1 "Motion"'s one continuous-motion
// carve-out, and it keeps its own pacing regardless of `motion.enabled`.
//
// M16 Task 5: this is the shell's one instance of PowerPanel (shell.qml
// wires the same `powerPanelInstance` into every screen's Bar), the
// natural, already-live home for the low-battery watcher below, since a
// per-screen widget (Battery.qml) would otherwise fire the same warning
// once per monitor. `_percent`/`_charging` are real property bindings that
// update regardless of whether the panel is open, so the watcher runs
// continuously in the background exactly like the rest of this panel's
// state already does.
Panel {
    id: root

    panelIcon: root._hasBattery ? "battery" : "zap"
    panelTitle: "Power"
    // A hero plus a short profile list, no ledger with competing columns:
    // the same shape as Weather's own Narrow, and the closest sanctioned
    // step to upstream's own 299px power panel.
    panelWidth: Theme.space.popupWidthNarrow

    readonly property var _device: UPower.displayDevice
    readonly property bool _hasBattery: root._device ? root._device.isLaptopBattery : false
    readonly property bool _charging: root._hasBattery && root._device.state === UPowerDeviceState.Charging
    readonly property int _percent: root._hasBattery ? Math.round(root._device.percentage * 100) : 0
    readonly property real _timeToEmpty: root._hasBattery ? root._device.timeToEmpty : 0
    readonly property real _timeToFull: root._hasBattery ? root._device.timeToFull : 0
    readonly property real _changeRate: root._hasBattery ? root._device.changeRate : 0

    // Charge-threshold detection (M26 Task 3): UPower's own AC-vs-battery
    // aggregate, not a per-device state parse, and the states object the
    // Power/model.js checks need, shared by the icon, the hero meta line and
    // the stats ledger below so none of the three can disagree.
    readonly property bool _onBattery: UPower.onBattery
    readonly property var _upowerStates: ({
        PendingCharge: UPowerDeviceState.PendingCharge,
        FullyCharged: UPowerDeviceState.FullyCharged,
        Charging: UPowerDeviceState.Charging
    })
    readonly property bool _thresholdActive: root._hasBattery
        ? Power.chargeThresholdActive(root._percent, root._device.state, root._changeRate, root._timeToFull, root._onBattery, root._upowerStates)
        : false
    readonly property string _batteryIcon: root._hasBattery
        ? Power.batteryIcon(root._percent, root._onBattery, root._thresholdActive, root._warnPercentPref)
        : "zap"
    readonly property string _stateLabel: root._hasBattery
        ? Power.chargeStateLabel(root._percent, root._device.state, root._onBattery, root._thresholdActive, root._upowerStates)
        : ""

    // Hysteresis state for Power/model.js's warnEvent(), persisted here
    // across calls, never reset except by the model's own re-arm-on-charge
    // rule. See model.js's own header comment for the full behavior.
    readonly property real _warnPercentPref: Config.get("battery.warnPercent", 10)
    readonly property real _criticalPercentPref: Config.get("battery.criticalPercent", 5)
    property var _batteryFired: Power.initialFired()
    property var _lastBatteryPercent: null

    // The watcher's charging input is "anything that isn't actively
    // draining" (Charging/FullyCharged/PendingCharge re-arm), not the
    // pulse's narrow state === Charging: a battery sitting at 100% on AC
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
    // threshold, which never generates a "changed" signal of its own; the
    // on_*Changed handlers below cover every real transition after that
    // (UPower keeps updating percentage/state independently of whether this
    // panel is open).
    Component.onCompleted: root._checkBatteryThresholds()
    on_PercentChanged: root._checkBatteryThresholds()
    on_ChargingChanged: root._checkBatteryThresholds()
    on_HasBatteryChanged: root._checkBatteryThresholds()
    on_DrainingChanged: root._checkBatteryThresholds()

    // Fixed order matching the PowerProfile enum, so `_profiles[i] === i`.
    // PowerProfilesQml exposes no enumerable "available profiles" list, only
    // `hasPerformanceProfile`; a rejected Performance write just leaves the
    // live ActiveProfile DBus property (and this binding) unchanged, which
    // is the honest self-correcting behaviour rather than something this
    // panel needs to gate by hand.
    readonly property var _profiles: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]

    cursorCount: root._profiles.length

    onCursorActivated: index => root._applyProfile(index)

    onIsOpenChanged: {
        if (root.isOpen) {
            // The cursor starts on the active profile, so the reveal-only
            // first keypress shows it where the eye already is.
            root.cursorIndex = Math.max(0, root._profiles.indexOf(PowerProfiles.profile));
            root.cursorSection = 0;
        } else {
            // Drop the RAPL baseline on close (M20 Task 5c): no background
            // polling for a closed panel, and reopening starts a fresh pair
            // of samples rather than computing a wattage across whatever gap
            // the panel was closed for.
            root._raplPrev = null;
            root.cpuPackageW = null;
        }
    }

    // CPU package power (M20 Task 5c, owner ask: "the W usage right next
    // to the W it's charging with"). Two `energy_uj` reads a fixed
    // interval apart, watts = delta / interval, the same idiom as
    // NetworkPanel's speed-test sampler (`cat` straight to argv, no
    // shell, a pure-JS reducer in Power/model.js does the math). RAPL's
    // `energy_uj` is root-only by default (PLATYPUS mitigation); a udev
    // rule outside this repo can make it user-readable. Either way,
    // `cat`'s stdout on a permission-denied or absent path comes up short
    // a line, `Power.parseRaplUj` returns null, and `cpuPackageW` stays
    // null rather than 0 or a guess.
    property var _raplPrev: null // {uj, maxUj, t} | null
    property var cpuPackageW: null

    readonly property string _raplEnergyPath: "/sys/class/powercap/intel-rapl:0/energy_uj"
    readonly property string _raplMaxRangePath: "/sys/class/powercap/intel-rapl:0/max_energy_range_uj"
    readonly property int _raplSampleIntervalMs: 2000

    function _sampleRapl() {
        if (raplProc.running)
            return;
        raplProc.command = ["cat", root._raplEnergyPath, root._raplMaxRangePath];
        raplProc.running = true;
    }

    Process {
        id: raplProc
        stdout: StdioCollector {
            id: raplCollector
        }
        onExited: exitCode => {
            var parsed = Power.parseRaplUj(raplCollector.text);
            if (!parsed) {
                root._raplPrev = null;
                root.cpuPackageW = null;
                return;
            }
            var t = Date.now();
            if (root._raplPrev)
                root.cpuPackageW = Power.raplWatts(root._raplPrev.uj, parsed.energyUj, parsed.maxRangeUj, t - root._raplPrev.t);
            root._raplPrev = { uj: parsed.energyUj, maxUj: parsed.maxRangeUj, t: t };
        }
    }

    Timer {
        id: raplTimer
        interval: root._raplSampleIntervalMs
        repeat: true
        running: root.isOpen
        triggeredOnStart: true
        onTriggered: root._sampleRapl()
    }

    function _applyProfile(index) {
        if (index < 0 || index >= root._profiles.length)
            return;
        root.cursorIndex = index;
        PowerProfiles.profile = root._profiles[index];
    }

    PanelHero {
        id: batteryHero
        visible: root._hasBattery
        width: parent.width
        title: "Battery"
        meta: root._stateLabel
        readout: root._hasBattery ? root._percent + "%" : ""
        rail: root._hasBattery ? root._percent / 100 : -1

        leading: Component {
            Icon {
                name: root._batteryIcon
                size: Theme.fontSize.heading
                color: batteryHero.foreground

                // Gated on root.isOpen (M16 Task 12): this panel's content
                // is instantiated once for the shell's whole lifetime
                // (Panel.qml hides the window rather than destroying it), so
                // an unqualified `running: root._charging` kept animating a
                // fully hidden window for as long as the laptop stayed on AC.
                SequentialAnimation on opacity {
                    running: root._charging && root.isOpen
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.4; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                    NumberAnimation { to: 1.0; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                }
            }
        }
    }

    // Stats ledger (M26 Task 3): two half-width cells for the short
    // readings, two full-width ones for the values that can run long (the
    // rate row's optional CPU suffix). "Charge cycles" is not in this
    // ledger, verified against the pinned quickshell source
    // (services/upower/device.hpp / org.freedesktop.UPower.Device.xml):
    // UPowerDevice exposes no cycle-count property at all. Battery size
    // (energyCapacity, a real UPower Wh reading) fills that slot instead;
    // healthPercentage (the DBus "Capacity" property, already "design
    // capacity as a percentage") covers design capacity. Every row here
    // reads a live UPowerDevice binding directly, never an async-populated
    // cache, so the four rows stay mounted for the panel's whole lifetime
    // (`visible: root._hasBattery`, same gate as the hero): an AC
    // plug/unplug only ever changes a row's value text, never its presence.
    Grid {
        id: batteryStatsGrid
        visible: root._hasBattery
        width: parent.width
        columns: 2
        columnSpacing: Theme.space.rowGap

        Cell {
            id: capacityCell
            width: (batteryStatsGrid.width - batteryStatsGrid.columnSpacing) / 2

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                SectionLabel { text: "CAPACITY" }

                Text {
                    width: parent.width
                    text: root._hasBattery ? Power.formatHealthPercent(root._device.healthPercentage, root._device.healthSupported) : ""
                    color: capacityCell.foreground
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSize.body
                    elide: Text.ElideRight
                }
            }
        }

        Cell {
            id: sizeCell
            width: (batteryStatsGrid.width - batteryStatsGrid.columnSpacing) / 2

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                SectionLabel { text: "SIZE" }

                Text {
                    width: parent.width
                    text: root._hasBattery ? Power.formatWh(root._device.energyCapacity) : ""
                    color: sizeCell.foreground
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSize.body
                    elide: Text.ElideRight
                }
            }
        }
    }

    Cell {
        id: timeStatCell
        visible: root._hasBattery
        width: parent.width

        Item {
            width: parent.width
            height: Math.max(timeStatLabel.implicitHeight, timeStatValue.implicitHeight)

            SectionLabel {
                id: timeStatLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Power.timeRowLabel(root._charging)
            }

            Text {
                id: timeStatValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root._hasBattery ? Power.timeRowValue(root._charging, root._timeToFull, root._timeToEmpty) : ""
                color: timeStatCell.foreground
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSize.body
            }
        }
    }

    Cell {
        id: rateStatCell
        visible: root._hasBattery
        width: parent.width

        Item {
            width: parent.width
            height: Math.max(rateStatLabel.implicitHeight, rateStatValue.implicitHeight)

            SectionLabel {
                id: rateStatLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Power.rateRowLabel(root._charging, root._thresholdActive)
            }

            Text {
                id: rateStatValue
                anchors.left: rateStatLabel.right
                anchors.leftMargin: Theme.space.iconGap
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: root._hasBattery ? Power.rateRowValue(root._changeRate, root.cpuPackageW) : ""
                color: rateStatCell.foreground
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSize.body
                elide: Text.ElideRight
            }
        }
    }

    Cell {
        visible: !root._hasBattery
        width: parent.width

        SectionLabel { text: "AC POWER" }
    }

    Component {
        id: profileRow

        Cell {
            id: profileCell
            required property int index
            required property var modelData
            width: parent.width
            interactive: true
            selected: profileCell.modelData === PowerProfiles.profile
            cursor: root.cursorActive && profileCell.index === root.cursorIndex

            onContainsPointerChanged: if (profileCell.containsPointer) {
                root.cursorActive = true;
                root.cursorIndex = profileCell.index;
            }

            onClicked: root._applyProfile(profileCell.index)

            Item {
                width: parent.width
                height: profileLabel.implicitHeight

                Text {
                    id: profileLabel
                    anchors.left: parent.left
                    anchors.right: profileCheck.left
                    anchors.rightMargin: Theme.space.iconGap
                    anchors.verticalCenter: parent.verticalCenter
                    text: PowerProfile.toString(profileCell.modelData)
                    color: profileCell.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                    elide: Text.ElideRight
                }

                Icon {
                    id: profileCheck
                    name: "check"
                    size: Theme.fontSize.body
                    visible: profileCell.selected
                    color: profileCell.foreground
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.space.rowGap

        SectionLabel { text: "PROFILE" }

        Repeater {
            model: root._profiles
            delegate: profileRow
        }
    }
}

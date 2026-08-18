import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Core
import qs.Components
import qs.Notifications
import "../../Power/model.js" as Power

// Power panel (DESIGN.md §Panels, spec §2, M6 Task 7): the shared
// PanelHero (M26 Task 1) opens the panel — battery glyph, "Battery",
// four-way state meta line, percent as the displayLarge readout, charge
// level as the rail — then a ruled stats ledger (M26 Task 3), then a
// keyboard-navigable power-profile picker under a PROFILE header, the
// active profile inverted. Bound directly to Quickshell.Services.UPower,
// same as AudioPanel binds Pipewire directly. The test VM's QEMU aarch64
// "virt" machine has no battery at all — UPower.displayDevice.isLaptopBattery
// is then false and the panel renders the honest "AC POWER" cell instead
// of a lying 0%, mirroring Bluetooth's "NO ADAPTER" state.
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
    // A hero plus a short PROFILE list, no ledger with competing columns —
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
    // Power/model.js checks need — shared by the glyph, the hero meta line,
    // and the stats ledger below so none of the three can disagree.
    readonly property bool _onBattery: UPower.onBattery
    readonly property var _upowerStates: ({
        PendingCharge: UPowerDeviceState.PendingCharge,
        FullyCharged: UPowerDeviceState.FullyCharged,
        Charging: UPowerDeviceState.Charging
    })
    readonly property bool _thresholdActive: root._hasBattery
        ? Power.chargeThresholdActive(root._percent, root._device.state, root._changeRate, root._timeToFull, root._onBattery, root._upowerStates)
        : false
    readonly property string _batteryGlyph: root._hasBattery
        ? Power.batteryGlyph(root._percent, root._onBattery, root._thresholdActive)
        : ""
    readonly property string _stateLabel: root._hasBattery
        ? Power.chargeStateLabel(root._percent, root._device.state, root._onBattery, root._thresholdActive, root._upowerStates)
        : ""

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
        } else {
            // Drop the RAPL baseline on close (M20 Task 5c) — no
            // background polling for a closed panel, and reopening starts
            // a fresh pair of samples rather than computing a wattage
            // across whatever gap the panel was closed for.
            root._raplPrev = null;
            root.cpuPackageW = null;
        }
    }

    // CPU package power (M20 Task 5c, owner ask: "the W usage right next
    // to the W it's charging with"). Two `energy_uj` reads a fixed
    // interval apart, watts = delta / interval — same idiom as
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
            // First Up/Down only reveals the cursor on the active profile
            // (M26 Task 8, upstream's CursorSurface contract) — it does not
            // also move it, so the highlight appears where the user can see
            // it before anything happens.
            if (!root.cursorActive && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                root.cursorActive = true;
                event.accepted = true;
                return;
            }
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

    PanelHero {
        visible: root._hasBattery
        width: parent.width
        glyph: root._batteryGlyph
        title: "Battery"
        meta: root._stateLabel
        readout: root._hasBattery ? root._percent + "%" : ""
        readoutSize: "displayLarge"
        rail: root._hasBattery ? root._percent / 100 : -1
    }

    // Stats ledger (M26 Task 3): two ruled half-width cells for the short
    // readings, two ruled full-width cells for the two whose value can run
    // long (the wattage row's optional CPU suffix). "Charge cycles" is not
    // in this ledger — verified against the pinned quickshell source
    // (services/upower/device.hpp / org.freedesktop.UPower.Device.xml):
    // UPowerDevice exposes no cycle-count property at all. Battery size
    // (energyCapacity, a real UPower Wh reading) fills that slot instead;
    // healthPercentage (the DBus "Capacity" property, already "design
    // capacity as a percentage") covers design capacity. Every row here
    // reads a live UPowerDevice binding directly, never an async-populated
    // cache, so the four rows stay mounted for the panel's whole lifetime
    // (`visible: root._hasBattery`, same gate as the hero) — an AC
    // plug/unplug only ever changes a row's value text, never its
    // presence.
    Grid {
        id: batteryStatsGrid
        visible: root._hasBattery
        width: parent.width
        columns: 2

        Cell {
            id: capacityCell
            width: batteryStatsGrid.width / 2

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                MetaLabel { text: "CAPACITY" }
                Text {
                    width: parent.width
                    text: root._hasBattery ? Power.formatHealthPercent(root._device.healthPercentage, root._device.healthSupported) : ""
                    color: capacityCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                    elide: Text.ElideRight
                }
            }
        }

        Cell {
            id: sizeCell
            width: batteryStatsGrid.width / 2

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                MetaLabel { text: "SIZE" }
                Text {
                    width: parent.width
                    text: root._hasBattery ? Power.formatWh(root._device.energyCapacity) : ""
                    color: sizeCell.foreground
                    font.family: Theme.fontFamily
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

        Row {
            width: parent.width
            spacing: Theme.space.sm

            MetaLabel { id: timeStatLabel; text: Power.timeRowLabel(root._charging); colon: true }
            Text {
                width: parent.width - timeStatLabel.implicitWidth - parent.spacing
                text: root._hasBattery ? Power.timeRowValue(root._charging, root._timeToFull, root._timeToEmpty) : ""
                color: timeStatCell.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
                elide: Text.ElideRight
            }
        }
    }

    // No colon on the rate row (DESIGN §2 item 10): the value is already
    // fused with its own CHARGING/DRAW word via formatWattageRow.
    Cell {
        id: rateStatCell
        visible: root._hasBattery
        width: parent.width

        Row {
            width: parent.width
            spacing: Theme.space.sm

            MetaLabel { id: rateStatLabel; text: "RATE" }
            Text {
                width: parent.width - rateStatLabel.implicitWidth - parent.spacing
                text: root._hasBattery
                    ? (root._thresholdActive ? "HOLDING" : Power.formatWattageRow(root._charging, root._changeRate, root.cpuPackageW))
                    : ""
                color: rateStatCell.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
                elide: Text.ElideRight
            }
        }
    }

    Cell {
        visible: !root._hasBattery
        width: parent.width

        MetaLabel { text: "AC POWER"; colon: true }
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
            hovered: root.cursorActive && profileCell.index === root._cursor
            onContainsPointerChanged: if (profileCell.containsPointer) {
                root.cursorActive = true;
                root._cursor = profileCell.index;
            }

            ActionLabel {
                text: PowerProfile.toString(profileCell.modelData)
                color: profileCell.foreground
            }

            interactive: true
            onClicked: root._applyProfile(profileCell.index)
        }
    }

    Repeater {
        model: root._profiles
        delegate: profileRow
    }
}

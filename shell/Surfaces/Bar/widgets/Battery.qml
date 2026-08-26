import QtQuick
import Quickshell.Services.UPower
// Aliased, not a bare `import qs.Core`: right-click reaches Core.State
// (the label toggle's persisted override) alongside a bare import, which
// loses the singleton to QtQuick's own colliding `State` name (the M24
// chevron trap, CLAUDE.md). Every Core.* reference in this file goes
// through the Core. prefix, not just the new ones, since qmllint's module
// resolution breaks the moment qs.Core is imported both ways in one file.
import qs.Core as Core
import qs.Components
import "../../../Power/model.js" as Power

// Bar cell for the laptop battery (DESIGN.md §3 Bar, spec "Surfaces"): a
// state icon plus the percentage in mono, click toggles the power panel
// anchored under this cell, same open-panel line as every other M6 widget.
// Hidden entirely (never a stub "0%") when UPower.displayDevice reports no
// laptop battery: isLaptopBattery is UPower's own sanctioned "is this a
// real battery" check (type === Battery && powerSupply === true; the
// aggregate AC-only displayDevice the test VM reports fails it), so this
// cell's `visible: false` drops it out of Bar.qml's Row entirely rather
// than leaving a dead slot, DESIGN's honest-unavailable-state rule pushed
// all the way to "don't show the cell at all". The icon is charge-aware
// (Power/model.js's batteryIcon), shared with PowerPanel's hero so the bar
// and the panel can never disagree.
//
// Critical battery (M16 Task 5): at or below battery.criticalPercent while
// discharging, the cell takes Cell's `destructive` state, and the warn band
// between battery.warnPercent and battery.criticalPercent takes `warning`.
// Both paint the border and the ink rather than filling the cell (DESIGN.md
// §5: colour goes on the border, never a full-bleed row). Charging past the
// threshold drops back to normal immediately: it's a live state, not a
// one-shot alarm. The two are mutually exclusive, critical always winning.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    readonly property var _device: UPower.displayDevice
    readonly property bool _hasBattery: root._device ? root._device.isLaptopBattery : false
    readonly property int _percent: root._hasBattery ? Math.round(root._device.percentage * 100) : 0
    readonly property bool _discharging: root._hasBattery && root._device.state === UPowerDeviceState.Discharging
    readonly property bool _charging: root._hasBattery && root._device.state === UPowerDeviceState.Charging
    readonly property real _warnPercent: Core.Config.get("battery.warnPercent", 10)
    readonly property bool _critical: root._discharging && root._percent <= Core.Config.get("battery.criticalPercent", 5)
    readonly property bool _low: root._discharging && !root._critical && root._percent <= root._warnPercent
    // UPower's own AC-vs-battery aggregate (device.state can lag on some
    // drivers), and PowerPanel's own charge-threshold detection mirrored
    // here so the bar cell and the panel never disagree (M26 Task 3).
    readonly property bool _onBattery: UPower.onBattery
    readonly property var _upowerStates: ({
        PendingCharge: UPowerDeviceState.PendingCharge,
        FullyCharged: UPowerDeviceState.FullyCharged,
        Charging: UPowerDeviceState.Charging
    })
    readonly property bool _thresholdActive: root._hasBattery
        ? Power.chargeThresholdActive(root._percent, root._device.state, root._device.changeRate, root._device.timeToFull, root._onBattery, root._upowerStates)
        : false
    readonly property string _icon: root._hasBattery
        ? Power.batteryIcon(root._percent, root._onBattery, root._thresholdActive, root._warnPercent)
        : "battery"

    // Read by Bar.qml's regionDelegate instead of `visible` directly: see
    // that file's own header comment for why crossing the Loader boundary
    // through the built-in `visible` property specifically breaks its own
    // future reactivity.
    readonly property bool shown: root._hasBattery

    // Visible by default (owner's explicit instruction, M23): unlike
    // weather/audio the percentage is content, not a repeat of the icon.
    // Right-click flips Core.State's own override (M26 Task 9); null there
    // means no override yet, so the settings.json default still applies.
    readonly property bool _showLabel: Core.State.batteryShowPercent !== null
        ? Core.State.batteryShowPercent
        : Core.Config.get("bar.widgets.battery.showLabel", true)

    visible: root.shown
    destructive: root._critical
    warning: root._low

    // What the percentage can't say: how long it is worth. UPower reports 0
    // for whichever estimate doesn't apply (timeToFull while discharging,
    // timeToEmpty while charging) and for both while it has no reading at
    // all (PowerPanel.qml's own note on the same fields), so the state name
    // is the honest fallback rather than a guessed time. The trailing
    // " / RIGHT ..." segment states the M26 Task 9 secondary action,
    // otherwise a right-click toggle is undiscoverable.
    tooltipText: {
        if (!root._hasBattery)
            return "";
        var head = "BATTERY " + root._percent + "%";
        var body;
        if (root._thresholdActive)
            body = head + " / THRESHOLD";
        else if (root._charging && root._device.timeToFull > 0)
            body = head + " / FULL IN " + Power.formatDuration(root._device.timeToFull);
        else if (root._discharging && root._device.timeToEmpty > 0)
            body = head + " / " + Power.formatDuration(root._device.timeToEmpty) + " LEFT";
        else
            body = head + " / " + Power.chargeStateLabel(root._percent, root._device.state, root._onBattery, root._thresholdActive, root._upowerStates);
        return body + " / RIGHT " + (root._showLabel ? "HIDE %" : "SHOW %");
    }

    // The percent label resizes this cell as it ticks: glide the width
    // instead of shoving the bar's other widgets instantly (DESIGN.md §1
    // "Motion", M16 Task 2's contract, extended to every numeric bar cell
    // by M26 Task 7).
    Behavior on implicitWidth {
        NumberAnimation { duration: Core.Theme.motion.standard; easing.type: Core.Theme.motion.easingInOut }
    }

    CellRow {
        spacing: Core.Theme.space.xs

        Icon {
            name: root._icon
            color: root.foreground
        }

        CellLabel {
            visible: root._showLabel
            text: root._percent + "%"
        }
    }

    panelOpen: root._panelOpen

    interactive: true
    // M26 Task 9: right click flips the percentage on and off, both left
    // and middle open the power panel (upstream's own redundant left/middle
    // idiom for a bar cell whose whole point is opening a panel,
    // `manual/05-the-top-bar.md`'s Audio row).
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            Core.State.setBatteryShowPercent(!root._showLabel);
        } else if (root.panel) {
            root.panel.toggleFrom(root);
        }
    }
}

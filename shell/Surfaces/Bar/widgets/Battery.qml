import QtQuick
import Quickshell.Services.UPower
import qs.Core
import qs.Components
import "../../../Power/model.js" as Power

// Bar cell for the laptop battery (DESIGN.md §Bar's own "battery cell BAT / 87%"
// meta idiom, spec §1, M6 Task 7): a level glyph plus the BAT / NN% meta
// label, click toggles the power panel anchored under this cell — same
// panel-open accent dot idiom as every other M6 widget. Hidden entirely
// (never a stub "BAT / 0%") when UPower.displayDevice reports no laptop
// battery — isLaptopBattery is UPower's own sanctioned "is this a real
// battery" check (type === Battery && powerSupply === true; the aggregate
// AC-only displayDevice the test VM reports fails it, so this cell's
// `visible: false` drops it out of Bar.qml's Row entirely rather than
// leaving a dead slot — DESIGN's honest-unavailable-state rule pushed all
// the way to "don't show the cell at all". Glyph ramp is charge-aware
// (M26 Task 3, Power/model.js's batteryGlyph): a genuine AC charge draws
// from the bolt ramp, discharging and the charge-threshold state (still
// plugged in, not visibly climbing) share the plain ramp, both converging
// on the same glyph at 100%. Codepoints taken from the pinned
// nerd-fonts-jetbrains-mono cmap (nix/testvm.nix).
//
// Critical battery (M16 Task 5, DESIGN.md §2.4): at/below
// battery.criticalPercent while discharging, the cell goes full-bleed
// urgent — Cell's own `urgent` state, same fill Model.js's model would
// give a critical toast, never a tinted border. Charging past the
// threshold (still plugged in, recovering) drops back to normal
// immediately — it's a live state, not a one-shot alarm.
//
// Low-but-not-critical battery (M18 Task 7, DESIGN.md §1.5/§2.4): the same
// thresholds Power/model.js's warnEvent() already tri-states (ok/warn/
// critical) drive a full-bleed `warning` cell between battery.warnPercent
// and battery.criticalPercent while discharging — no threshold invented
// here, just the existing warn band spending the palette's `warning` role.
// Mutually exclusive with `_critical`: the critical band always wins.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    readonly property var _device: UPower.displayDevice
    readonly property bool _hasBattery: root._device ? root._device.isLaptopBattery : false
    readonly property int _percent: root._hasBattery ? Math.round(root._device.percentage * 100) : 0
    readonly property bool _discharging: root._hasBattery && root._device.state === UPowerDeviceState.Discharging
    readonly property bool _charging: root._hasBattery && root._device.state === UPowerDeviceState.Charging
    readonly property bool _critical: root._discharging && root._percent <= Config.get("battery.criticalPercent", 5)
    readonly property bool _low: root._discharging && !root._critical && root._percent <= Config.get("battery.warnPercent", 10)
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
    readonly property string _glyph: root._hasBattery ? Power.batteryGlyph(root._percent, root._onBattery, root._thresholdActive) : ""

    // Read by Bar.qml's regionDelegate instead of `visible` directly — see
    // that file's own header comment for why crossing the Loader boundary
    // through the built-in `visible` property specifically breaks its own
    // future reactivity.
    readonly property bool shown: root._hasBattery

    // Visible by default (owner's explicit instruction, M23): unlike
    // weather/audio the percentage is content, not a repeat of the glyph.
    readonly property bool _showLabel: Config.get("bar.widgets.battery.showLabel", true)

    visible: root.shown
    standalone: true
    urgent: root._critical
    warning: root._low

    // What the BAT / NN% label can't say: how long that percentage is worth.
    // UPower reports 0 for whichever estimate doesn't apply — timeToFull
    // while discharging, timeToEmpty while charging — and for both while it
    // has no reading at all (PowerPanel.qml's own note on the same fields),
    // so the state name is the honest fallback rather than a guessed time.
    tooltipText: {
        if (!root._hasBattery)
            return "";
        var head = "BATTERY " + root._percent + "%";
        if (root._thresholdActive)
            return head + " / THRESHOLD";
        if (root._charging && root._device.timeToFull > 0)
            return head + " / FULL IN " + Power.formatDuration(root._device.timeToFull);
        if (root._discharging && root._device.timeToEmpty > 0)
            return head + " / " + Power.formatDuration(root._device.timeToEmpty) + " LEFT";
        return head + " / " + Power.chargeStateLabel(root._percent, root._device.state, root._onBattery, root._thresholdActive, root._upowerStates);
    }

    // The percent label resizes this cell as it ticks — glide the width
    // instead of shoving the bar's other widgets instantly (DESIGN.md §4,
    // M16 Task 2's contract, extended to every numeric bar cell by M26
    // Task 7).
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        // Fixed-width slot (M26 Task 7): the glyph ramp swaps codepoints as
        // charge state changes, and a Nerd Font glyph's own advance width
        // varies by codepoint — without this, the swap alone would shift
        // the label next to it even with the implicitWidth glide above.
        Item {
            id: glyphSlot
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.space.huge
            height: glyphText.implicitHeight

            Text {
                id: glyphText
                anchors.centerIn: parent
                text: root._glyph
                color: root.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }
        }

        MetaLabel {
            visible: root._showLabel
            anchors.verticalCenter: parent.verticalCenter
            text: "BAT / " + root._percent + "%"
            color: root.dimForeground
        }
    }

    PanelOpenDot {
        visible: root._panelOpen
        inverted: root.invertedNow
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
    }

    interactive: true
    onClicked: {
        if (root.panel)
            root.panel.toggleFrom(root);
    }
}

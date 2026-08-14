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
// the way to "don't show the cell at all". Charging is communicated inside
// PowerPanel's breathing-opacity pulse, not here — no separate charging
// glyph set. Glyph codepoints taken from the pinned nerd-fonts-jetbrains-
// mono cmap (nix/testvm.nix), rounded to the nearest 10%: md-battery_outline
// U+F008E (0%), md-battery_NN U+F007A..F0082 (10%..90%), md-battery U+F0079
// (100%).
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
    readonly property string _glyph: {
        var bucket = Math.max(0, Math.min(100, Math.round(root._percent / 10) * 10));
        switch (bucket) {
        case 0: return "󰂎";
        case 10: return "󰁺";
        case 20: return "󰁻";
        case 30: return "󰁼";
        case 40: return "󰁽";
        case 50: return "󰁾";
        case 60: return "󰁿";
        case 70: return "󰂀";
        case 80: return "󰂁";
        case 90: return "󰂂";
        default: return "󰁹";
        }
    }

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
        if (root._charging && root._device.timeToFull > 0)
            return head + " / FULL IN " + Power.formatDuration(root._device.timeToFull);
        if (root._discharging && root._device.timeToEmpty > 0)
            return head + " / " + Power.formatDuration(root._device.timeToEmpty) + " LEFT";
        // Uppercased at display time by Tooltip.qml's own MetaLabel — the
        // JS-level `.toUpperCase()` this used to carry was pure redundancy
        // (audit "uppercase/meta treatment").
        return head + " / " + UPowerDeviceState.toString(root._device.state);
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root._glyph
            color: root.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
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
            root.panel.toggle(root.mapToItem(null, 0, 0).x);
    }
}

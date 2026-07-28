import QtQuick
import Quickshell.Services.UPower
import qs.Core
import qs.Components

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
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    readonly property var _device: UPower.displayDevice
    readonly property bool _hasBattery: root._device ? root._device.isLaptopBattery : false
    readonly property int _percent: root._hasBattery ? Math.round(root._device.percentage * 100) : 0
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

    visible: root._hasBattery
    hovered: hoverArea.containsMouse

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.xs

        Text {
            text: root._glyph
            color: root.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
        }

        MetaLabel {
            text: "BAT / " + root._percent + "%"
            color: root.foreground
        }
    }

    Rectangle {
        visible: root._panelOpen
        width: 4
        height: 4
        radius: Theme.radius
        color: Theme.color.accent
        anchors.top: parent.top
        anchors.right: parent.right
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.panel)
                root.panel.toggle(root.mapToItem(null, 0, 0).x);
        }
    }
}

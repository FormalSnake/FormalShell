import QtQuick
import qs.Core
import qs.Components

// Bar cell for DisplayPanel (DESIGN.md §3 "Bar", M36): one monitor icon,
// click toggles the display panel anchored under this cell, marked open by
// the same `panelOpen` underline as every other panel-bearing cell.
// Unlike every device-status cell above it, this one has no absent state to
// hide on (a session always has at least one output), so it carries no
// `shown` gate and is always visible once placed in `bar.layout`. It also
// carries no value at all: the panel is a consult surface (per-output
// on/off, scale, mirror, brightness), not a glance one, so there is no
// single number this cell could summarize honestly.
// `bar.widgets.display.showLabel` opts a name back in beside the icon
// (M23's opt-in-label idiom), for a host running this icon next to others
// that could otherwise read ambiguously.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    // Label-off by default, like every sibling whose icon already says what
    // the cell is (M23's weather/audio rule; owner 2026-08-19: "why does it
    // show DISPLAY in big? no other panel does this"). The name lives in
    // tooltipText.
    readonly property bool _showLabel: Config.get("bar.widgets.display.showLabel", false)

    tooltipText: "DISPLAY"

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xs

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "monitor"
            color: root.foreground
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root._showLabel
            text: "Display"
            color: root.foreground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.body
            font.weight: Theme.weight.medium
        }
    }

    panelOpen: root._panelOpen

    interactive: true
    onClicked: {
        if (root.panel)
            root.panel.toggleFrom(root);
    }
}

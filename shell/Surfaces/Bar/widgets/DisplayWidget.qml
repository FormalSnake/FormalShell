import QtQuick
import qs.Core
import qs.Components

// Bar cell for DisplayPanel (DESIGN.md §3 Bar, M36, plan at
// docs/superpowers/plans/2026-08-19-m36-display-bar-cell.md): a single
// monitor glyph, click toggles the display panel anchored under this cell,
// same PanelOpenDot idiom as every other M6 widget (BluetoothWidget.qml).
// Unlike every device-status cell above it, this one has no absent state
// to hide on — a session always has at least one output — so it carries
// no `shown` gate and is always visible once placed in `bar.layout`. It
// also carries no value text at all: the panel is a consult surface (per-
// output on/off, scale, mirror, brightness), not a glance one, so there is
// no single number this cell could summarize honestly. `showLabel` still
// gates an uppercase "DISPLAY" caption next to the glyph (M23's opt-in-
// label idiom, `bar.widgets.display.showLabel`), for a host running this
// glyph next to others that could otherwise read ambiguously. Glyph
// codepoint verified against the pinned nerd-fonts-jetbrains-mono cmap
// (nix/testvm.nix) via fonttools ttx, not memory: md-monitor U+F0379.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    // Visible by default (M23 precedent): the caption is content of its
    // own — naming a glyph-only cell — not a repeat of the glyph.
    readonly property bool _showLabel: Config.get("bar.widgets.display.showLabel", true)

    standalone: true
    tooltipText: "DISPLAY"

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        // Fixed-width slot (M26 Task 7), matching this cell's siblings even
        // though this glyph itself never swaps.
        Item {
            id: glyphSlot
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.space.huge
            height: glyphText.implicitHeight

            Text {
                id: glyphText
                anchors.centerIn: parent
                text: "󰍹"
                color: root.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }
        }

        MetaLabel {
            visible: root._showLabel
            anchors.verticalCenter: parent.verticalCenter
            text: "DISPLAY"
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

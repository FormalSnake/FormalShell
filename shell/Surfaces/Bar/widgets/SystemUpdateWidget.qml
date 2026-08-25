import QtQuick
import qs.Core
import qs.Components

// Bar cell for the flake-inputs-behind check: a glyph plus
// SystemUpdate/model.js's summaryLabel() verbatim, click toggles the panel
// anchored under this cell. Opt-in via bar.layout, never part of layout.js's
// DEFAULT_LAYOUT, and naming it there is the opt-in to background polling
// (TailscaleWidget/GithubWidget's own split: the poll lives in the panel, so
// `panel open systemupdate` renders honestly even when this cell never
// exists).
//
// Unlike the tailscale cell this one stays visible in every state, NO FLAKE
// included: it is opt-in, so the user asked for it, and a cell that vanishes
// because the config key is unset reads as a bug rather than as an answer.
// Every state's wording comes from the model, so the bar and the panel can
// never disagree.
//
// Behind inputs make the cell full-bleed `warning` (DESIGN.md §2.4), not an
// accent tint: this is a degraded-but-not-critical state, the same band
// Battery.qml spends on a low battery. Glyph codepoints from the pinned
// nerd-fonts-jetbrains-mono cmap (nix/testvm.nix), read out of the font's
// own format-12 subtable rather than memory: md-package_up U+F03D5 while
// anything is behind, md-package U+F03D3 otherwise.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    readonly property int _behind: root.panel ? root.panel.counts.behind : 0
    readonly property string _summary: root.panel ? root.panel.summary : "CHECKING"

    // Visible by default (M23): opt-in builtins absent from DEFAULT_LAYOUT
    // keep their reading unless a user who added the widget opts back out.
    readonly property bool _showLabel: Config.get("bar.widgets.systemUpdate.showLabel", true)

    standalone: true
    warning: root._behind > 0

    // The cell already carries the count; the tooltip names what it counts,
    // which "2 BEHIND" alone never says.
    tooltipText: "FLAKE INPUTS / " + root._summary

    Component.onCompleted: {
        if (root.panel)
            root.panel.pollEnabled = true;
    }

    // The BEHIND count and status summary resize this cell — glide the
    // width instead of shoving the bar's other widgets instantly
    // (DESIGN.md §4, M16 Task 2's contract, extended to every numeric bar
    // cell by M26 Task 7).
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        // Fixed-width slot (M26 Task 7): the glyph swaps between "behind"
        // and "up to date" states, and a Nerd Font glyph's own advance
        // width varies by codepoint.
        Item {
            id: glyphSlot
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.space.huge
            height: glyphText.implicitHeight

            Text {
                id: glyphText
                anchors.centerIn: parent
                text: root._behind > 0 ? "󰏕" : "󰏓"
                color: root.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }
        }

        MetaLabel {
            visible: root._showLabel
            anchors.verticalCenter: parent.verticalCenter
            text: root._summary
            color: root.dimForeground
        }
    }

    panelOpen: root._panelOpen

    interactive: true
    onClicked: {
        if (root.panel)
            root.panel.toggleFrom(root);
    }
}

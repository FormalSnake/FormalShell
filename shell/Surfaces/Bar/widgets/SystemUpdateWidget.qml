import QtQuick
import qs.Core
import qs.Components

// Bar cell for the flake-inputs-behind check (DESIGN.md §3 "Bar"): a package
// icon plus SystemUpdate/model.js's summaryLabel() verbatim, click toggles
// the panel anchored under this cell. Opt-in via bar.layout, never part of
// layout.js's DEFAULT_LAYOUT, and naming it there is the opt-in to
// background polling (TailscaleWidget/GithubWidget's own split: the poll
// lives in the panel, so `panel open systemupdate` renders honestly even
// when this cell never exists).
//
// Unlike the tailscale cell this one stays visible in every state, NO FLAKE
// included: it is opt-in, so the user asked for it, and a cell that vanishes
// because the config key is unset reads as a bug rather than as an answer.
// Every state's wording comes from the model, so the bar and the panel can
// never disagree.
//
// Behind inputs make the cell `warning`, not `destructive`: this is a
// degraded-but-not-critical state, the same band Battery.qml spends on a low
// battery.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    readonly property int _behind: root.panel ? root.panel.counts.behind : 0
    readonly property string _summary: root.panel ? root.panel.summary : "Checking"

    // Visible by default (M23): opt-in builtins absent from DEFAULT_LAYOUT
    // keep their reading unless a user who added the widget opts back out.
    readonly property bool _showLabel: Config.get("bar.widgets.systemUpdate.showLabel", true)

    warning: root._behind > 0

    // The cell already carries the count; the tooltip names what it counts,
    // which "2 behind" alone never says.
    tooltipText: "FLAKE INPUTS / " + root._summary

    Component.onCompleted: {
        if (root.panel)
            root.panel.pollEnabled = true;
    }

    // The BEHIND count and status summary resize this cell: glide the width
    // instead of shoving the bar's other widgets instantly (DESIGN.md §1
    // "Motion").
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xs

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root._behind > 0 ? "package-plus" : "package"
            color: root.foreground
        }

        // The summary is the model's own one tested string, states and
        // counts alike, so it renders as the one label that is allowed to
        // uppercase rather than being split into a figure and a word here.
        SectionLabel {
            anchors.verticalCenter: parent.verticalCenter
            visible: root._showLabel
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

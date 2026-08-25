import QtQuick
import qs.Core
import qs.Components

// Bar cell for GitHub activity (DESIGN.md §3 "Bar"): a branch icon plus
// "n/m" in mono for open PRs authored by the user and open issues assigned
// to them. The poll itself lives in GithubPanel.qml (one shared `gh api
// graphql` Process instead of one per screen's bar; see that file's header
// for the IPC-open rationale), so this cell just flips the panel's
// pollEnabled on (the widget being named in bar.layout is the user's opt-in
// to background gh calls; it's never part of layout.js's DEFAULT_LAYOUT, so
// the no-config bar is unchanged) and binds the results. Click toggles the
// panel anchored under this cell. Honest states mirror the panel's poll
// state: gh missing hides the cell entirely (Battery's `shown` pattern, see
// Bar.qml's header for why `shown` and not `visible` crosses the Loader
// boundary); auth failure renders a dim NO AUTH label, any other failure a
// dim NO GH one, never stale counts and never invented ones. Hidden until
// the first poll returns at all.
Cell {
    id: root

    property var panel: null

    readonly property string _state: root.panel ? root.panel.pollState : "unknown"
    readonly property int _prs: root.panel ? root.panel.prCount : 0
    readonly property int _issues: root.panel ? root.panel.issueCount : 0
    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    // Visible by default (M23): opt-in builtins absent from DEFAULT_LAYOUT
    // keep their reading unless a user who added the widget opts back out.
    readonly property bool _showLabel: Config.get("bar.widgets.github.showLabel", true)

    // Read by Bar.qml's regionDelegate instead of `visible` directly, see
    // that file's own header comment.
    readonly property bool shown: root._state !== "unknown" && root._state !== "missing"

    visible: root.shown

    // "3/7" is unreadable without knowing which number is which.
    tooltipText: root._state === "ok"
        ? "GITHUB / " + root._prs + " PRS " + root._issues + " ISSUES"
        : (root._state === "noauth" ? "GITHUB / NOT AUTHENTICATED" : "GITHUB / UNAVAILABLE")

    Component.onCompleted: {
        if (root.panel)
            root.panel.pollEnabled = true;
    }

    // The PR/issue counts resize this cell as they change: glide the width
    // instead of shoving the bar's other widgets instantly (DESIGN.md §1
    // "Motion").
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    // A Row rather than siblings dropped straight into the cell: Cell's own
    // _measure() sizes off every direct child regardless of visibility, so
    // the counts state would otherwise stay as wide as the NO AUTH label.
    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xs

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "git-branch"
            color: root._state === "ok" ? root.foreground : root.dimForeground
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root._showLabel && root._state === "ok"
            text: root._prs + "/" + root._issues
            color: root.foreground
            font.family: Theme.fontFamilyMono
            font.pixelSize: Theme.fontSize.body
            font.weight: Theme.weight.medium
        }

        // The honest states are words, so they render as the one label that
        // is allowed to uppercase (MicWidget's own NO MIC idiom).
        SectionLabel {
            anchors.verticalCenter: parent.verticalCenter
            visible: root._showLabel && root._state !== "ok"
            text: root._state === "noauth" ? "NO AUTH" : "NO GH"
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

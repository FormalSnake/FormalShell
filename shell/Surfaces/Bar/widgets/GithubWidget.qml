import QtQuick
import qs.Core
import qs.Components

// Bar cell for GitHub activity (DESIGN.md §Bar, M12 Task 8, M13 Task 3):
// glyph + "N/M" meta label for open PRs authored by the user and open
// issues assigned to them. The poll itself lives in GithubPanel.qml since
// M13 Task 3 (one shared `gh api graphql` Process instead of one per
// screen's bar; see that file's header for the IPC-open rationale) — this
// cell just flips the panel's pollEnabled on (the widget being named in
// bar.layout is the user's opt-in to background gh calls; it's never part
// of layout.js's DEFAULT_LAYOUT, so the no-config bar is unchanged) and
// binds the results. Click toggles the panel anchored under this cell (the
// AudioWidget accent-dot idiom) instead of the old xdg-open jump. Honest
// states mirror the panel's poll state: gh missing hides the cell entirely
// (Battery's `shown` pattern — see Bar.qml's header for why `shown`, not
// `visible`, crosses the Loader boundary); auth failure renders a dim NO
// AUTH cell; any other failure a dim NO GH cell — never stale counts,
// never invented ones. Hidden until the first poll returns at all. Glyph
// from the pinned nerd-fonts-jetbrains-mono cmap (nix/testvm.nix) via
// fonttools ttx, not memory: oct-mark_github U+F408.
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

    // Read by Bar.qml's regionDelegate instead of `visible` directly — see
    // that file's own header comment.
    readonly property bool shown: root._state !== "unknown" && root._state !== "missing"

    visible: root.shown
    standalone: true
    hovered: hoverArea.containsMouse

    // "3/7" is unreadable without knowing which number is which.
    tooltipText: root._state === "ok"
        ? "GITHUB / " + root._prs + " PRS " + root._issues + " ISSUES"
        : (root._state === "noauth" ? "GITHUB / NOT AUTHENTICATED" : "GITHUB / UNAVAILABLE")

    Component.onCompleted: {
        if (root.panel)
            root.panel.pollEnabled = true;
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: root._state === "ok" ? root.foreground : root.dimForeground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
        }

        MetaLabel {
            visible: root._showLabel
            anchors.verticalCenter: parent.verticalCenter
            text: root._state === "ok"
                ? root._prs + "/" + root._issues
                : (root._state === "noauth" ? "NO AUTH" : "NO GH")
            color: root._state === "ok" ? root.foreground : root.dimForeground
        }
    }

    PanelOpenDot {
        visible: root._panelOpen
        inverted: root.invertedNow
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
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

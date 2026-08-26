import QtQuick
import qs.Core
import qs.Components

// Bar cell for AI usage, Claude Code and Codex rate limits (DESIGN.md §3
// "Bar"): a gauge icon plus the worst tracked window's percent in mono,
// taking the cell's `destructive` border and ink at or past 90%. The poll
// itself lives in UsagePanel.qml (GithubWidget's own precedent, see that
// file's header for the IPC-open rationale): this cell just flips the
// panel's pollEnabled on (naming "usage" in bar.layout is the opt-in to
// background credential reads and `codex app-server` spawns; it's never part
// of layout.js's DEFAULT_LAYOUT) and reflects its state. Click toggles the
// panel, and on a STALE Claude leg also asks the panel to have Claude Code
// refresh its own OAuth pair. Hidden until at least one enabled provider
// (usage.claude/usage.codex, both default true) has answered at all: an
// honest NO AUTH/NO CODEX state counts as an answer, and only the
// pre-first-poll "unknown" state hides the cell, same as GithubWidget's own
// `shown`.
Cell {
    id: root

    property var panel: null

    readonly property bool _claudeSettled: root.panel ? (root.panel.claudeEnabled && root.panel.claudeState !== "unknown") : false
    readonly property bool _codexSettled: root.panel ? (root.panel.codexEnabled && root.panel.codexState !== "unknown") : false
    readonly property real _worstPercent: root.panel ? root.panel.worstPercent : -1
    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    readonly property string _statusLabel: root.panel ? root.panel.statusLabel : ""

    // Read by Bar.qml's regionDelegate instead of `visible` directly, see
    // that file's own header comment.
    readonly property bool shown: root._claudeSettled || root._codexSettled

    // Visible by default (M23): opt-in builtins absent from DEFAULT_LAYOUT
    // keep their reading unless a user who added the widget opts back out.
    readonly property bool _showLabel: Config.get("bar.widgets.usage.showLabel", true)

    visible: root.shown
    destructive: root._worstPercent >= 0.9

    // No prior tooltip existed since the label was always on; now that the
    // label can be hidden per-widget, this carries the same percent/status
    // reading so hiding it never deletes information.
    tooltipText: "USAGE / " + (root._worstPercent >= 0 ? Math.round(root._worstPercent * 100) + "%" : (root._statusLabel !== "" ? root._statusLabel : "UNAVAILABLE"))

    Component.onCompleted: {
        if (root.panel)
            root.panel.pollEnabled = true;
    }

    // The worst-window percent resizes this cell: glide the width instead of
    // shoving the bar's other widgets instantly (DESIGN.md §1 "Motion").
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easingInOut }
    }

    // A Row rather than siblings dropped straight into the cell: Cell's own
    // _measure() sizes off every direct child regardless of visibility, so
    // the percent state would otherwise stay as wide as the status label.
    CellRow {
        spacing: Theme.space.xs

        Icon {
            name: "gauge"
            color: root._worstPercent >= 0 ? root.foreground : root.dimForeground
        }

        CellLabel {
            visible: root._showLabel && root._worstPercent >= 0
            text: root._worstPercent >= 0 ? Math.round(root._worstPercent * 100) + "%" : ""
        }

        // The honest states are words, so they render as the one label that
        // is allowed to uppercase (MicWidget's own NO MIC idiom).
        CellLabel {
            meta: true
            visible: root._showLabel && root._worstPercent < 0 && root._statusLabel !== ""
            text: root._statusLabel
        }
    }

    panelOpen: root._panelOpen

    interactive: true
    onClicked: {
        if (!root.panel)
            return;
        // Clicking a stale cell is an explicit "fix it", so it skips the
        // refresh cooldown (UsagePanel's own header) and the panel that
        // opens is already showing the attempt.
        if (root.panel.claudeState === "stale")
            root.panel.refreshClaudeToken(true);
        root.panel.toggleFrom(root);
    }
}

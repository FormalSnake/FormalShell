import QtQuick
import qs.Core
import qs.Components

// Bar cell for AI usage — Claude Code / Codex rate limits (DESIGN.md §Bar,
// M14 Task 7): glyph plus the worst tracked window's percent, alarming
// full-bleed urgent at >=90% utilization (DESIGN.md §2.4, Cell's own
// `urgent` full-bleed contract). The poll itself lives in UsagePanel.qml
// (GithubWidget's own precedent — see that file's header for the IPC-open
// rationale): this cell just flips the panel's pollEnabled on (naming
// "usage" in bar.layout is the opt-in to background credential reads and
// `codex app-server` spawns; it's never part of layout.js's DEFAULT_LAYOUT)
// and reflects its state. Click toggles the panel (AudioWidget's accent-dot
// idiom), and on a STALE Claude leg also asks the panel to have Claude Code
// refresh its own OAuth pair. Hidden until at least one enabled provider
// (usage.claude/usage.codex, both default true) has answered at all — an honest NO AUTH/
// NO CODEX cell counts as an answer; only the pre-first-poll "unknown"
// state hides the cell, same as GithubWidget's own `shown`. Glyph from the
// pinned nerd-fonts-jetbrains-mono cmap (nix/testvm.nix) via fonttools ttx,
// not memory: md-robot_excited U+F16A3.
Cell {
    id: root

    property var panel: null

    readonly property bool _claudeSettled: root.panel ? (root.panel.claudeEnabled && root.panel.claudeState !== "unknown") : false
    readonly property bool _codexSettled: root.panel ? (root.panel.codexEnabled && root.panel.codexState !== "unknown") : false
    readonly property real _worstPercent: root.panel ? root.panel.worstPercent : -1
    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    // Read by Bar.qml's regionDelegate instead of `visible` directly — see
    // that file's own header comment.
    readonly property bool shown: root._claudeSettled || root._codexSettled

    readonly property color _textColor: root._worstPercent >= 0 ? root.foreground : root.dimForeground

    // Visible by default (M23): opt-in builtins absent from DEFAULT_LAYOUT
    // keep their reading unless a user who added the widget opts back out.
    readonly property bool _showLabel: Config.get("bar.widgets.usage.showLabel", true)

    visible: root.shown
    standalone: true
    urgent: root._worstPercent >= 0.9

    // No prior tooltip existed since the label was always on; now that the
    // label can be hidden per-widget, this carries the same percent/status
    // reading so hiding it never deletes information.
    tooltipText: "USAGE / " + (root._worstPercent >= 0 ? Math.round(root._worstPercent * 100) + "%" : (root.panel ? root.panel.statusLabel : "UNAVAILABLE"))

    Component.onCompleted: {
        if (root.panel)
            root.panel.pollEnabled = true;
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󱚣"
            color: root._textColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
        }

        MetaLabel {
            visible: root._showLabel
            anchors.verticalCenter: parent.verticalCenter
            text: root._worstPercent >= 0 ? Math.round(root._worstPercent * 100) + "%" : (root.panel ? root.panel.statusLabel : "")
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
        if (!root.panel)
            return;
        // Clicking a stale cell is an explicit "fix it", so it skips the
        // refresh cooldown (UsagePanel's own header) and the panel that
        // opens is already showing the attempt.
        if (root.panel.claudeState === "stale")
            root.panel.refreshClaudeToken(true);
        root.panel.toggle(root.mapToItem(null, 0, 0).x);
    }
}

import QtQuick
import qs.Core
import qs.Components

// Bar cell for Tailscale status (DESIGN.md §Bar, M16 Task 8): a single
// glyph, dim while stopped/erroring, normal while connected — click toggles
// the panel anchored under this cell (AudioWidget's accent-dot idiom). The
// poll itself lives in TailscalePanel.qml (GithubWidget/GithubPanel's own
// split, M13 Task 3's rationale: one shared poll instead of one per screen's
// bar, and `panel open tailscale` over IPC must render honestly even when
// this widget is never named in bar.layout) — this cell just flips the
// panel's pollEnabled on (naming the widget in bar.layout is the opt-in to
// background `tailscale status` polling, same as github/usage; it's never
// part of layout.js's DEFAULT_LAYOUT) and binds the result. Hidden until the
// first poll resolves with the CLI actually present (GithubWidget's `shown`
// pattern — missing tailscale hides the cell entirely rather than showing a
// permanently-dim one). Glyph from the pinned nerd-fonts-jetbrains-mono cmap
// (nix/testvm.nix) via fonttools ttx, not memory: md-lan_connect U+F0318 —
// the mesh-connection glyph, not omarchy's custom-drawn dot-grid mark (this
// shell's icons are Nerd Font glyphs only, CLAUDE.md's hard rule).
Cell {
    id: root

    property var panel: null

    readonly property string _state: root.panel ? root.panel.pollState : "unknown"
    readonly property bool _running: root.panel && root.panel.status ? root.panel.status.running : false
    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    // Read by Bar.qml's regionDelegate instead of `visible` directly — see
    // that file's own header comment.
    readonly property bool shown: root._state !== "unknown" && root._state !== "missing"

    visible: root.shown
    standalone: true
    hovered: hoverArea.containsMouse

    // One glyph, dim or not — nothing on the cell says what it stands for.
    // Every branch is TailscalePanel.qml's own wording for the SAME poll
    // state, because `status` is documented meaningful only while pollState is
    // "ok" (it is null on the error path): reading `_running` unconditionally
    // would report STOPPED for a daemon that is running but not logged in, and
    // for a status reply this shell failed to parse at all — inventing a
    // daemon state never observed. The cell is visible for those states too,
    // so they need real wording rather than a default.
    tooltipText: {
        switch (root._state) {
        case "needsLogin": return "TAILSCALE / NEEDS LOGIN";
        case "error": return "TAILSCALE / NO TAILSCALE";
        case "ok": return "TAILSCALE / " + (root._running ? "CONNECTED" : "STOPPED");
        default: return "TAILSCALE";
        }
    }

    Component.onCompleted: {
        if (root.panel)
            root.panel.pollEnabled = true;
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰌘"
        color: root._running ? root.foreground : root.dimForeground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize.body
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

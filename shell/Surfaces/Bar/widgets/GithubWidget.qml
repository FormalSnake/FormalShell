import QtQuick
import Quickshell.Io
import qs.Core
import qs.Compositor
import qs.Components

// Bar cell for GitHub activity (DESIGN.md §Bar, M12 Task 8): polls one
// `gh api graphql` call every `github.intervalMs` (default 300000) for the
// count of open PRs the user authored and open issues assigned to them,
// rendered as a glyph + "N/M" meta label. Opt-in via bar.layout only —
// never part of layout.js's DEFAULT_LAYOUT, so the no-config bar is
// unchanged. Click opens github.com/notifications via xdg-open. Honest
// states, keyed off the sh wrapper's exit code: `gh` missing from PATH
// (the `command -v` guard, exit 127) hides the cell entirely (Battery's
// `shown` pattern — see Bar.qml's header for why `shown`, not `visible`,
// crosses the Loader boundary); gh's documented authentication exit code 4
// (`gh help exit-codes`) renders a dim NO AUTH cell; any other failure or
// unparsable output renders a dim NO GH cell — never stale counts, never
// invented ones. Hidden until the first poll returns at all: an empty cell
// before gh has answered would claim a state nobody has verified yet.
// Glyph from the pinned nerd-fonts-jetbrains-mono cmap (nix/testvm.nix)
// via fonttools ttx, not memory: oct-mark_github U+F408.
Cell {
    id: root

    // "unknown" (pre-first-poll) | "missing" | "noauth" | "error" | "ok"
    property string _state: "unknown"
    property int _prs: 0
    property int _issues: 0

    readonly property int _interval: {
        var v = Config.get("github.intervalMs", 300000);
        return (typeof v === "number" && v > 0) ? v : 300000;
    }

    // Read by Bar.qml's regionDelegate instead of `visible` directly — see
    // that file's own header comment.
    readonly property bool shown: root._state !== "unknown" && root._state !== "missing"

    visible: root.shown
    standalone: true
    hovered: hoverArea.containsMouse

    function _poll() {
        if (proc.running)
            return;
        proc.running = true;
    }

    Component.onCompleted: root._poll()

    Timer {
        interval: root._interval
        running: true
        repeat: true
        onTriggered: root._poll()
    }

    Process {
        id: proc
        command: ["sh", "-c", "command -v gh >/dev/null 2>&1 || exit 127; exec gh api graphql -f query='{ prs: search(query: \"is:open is:pr author:@me\", type: ISSUE) { issueCount } issues: search(query: \"is:open is:issue assignee:@me\", type: ISSUE) { issueCount } }'"]
        stdout: StdioCollector {
            id: collector
        }
        onExited: exitCode => {
            if (exitCode === 127) {
                root._state = "missing";
                return;
            }
            if (exitCode === 4) {
                root._state = "noauth";
                return;
            }
            if (exitCode !== 0) {
                root._state = "error";
                return;
            }
            try {
                var d = JSON.parse(collector.text);
                var prs = d.data.prs.issueCount;
                var issues = d.data.issues.issueCount;
                if (typeof prs !== "number" || typeof issues !== "number")
                    throw new Error("counts missing");
                root._prs = prs;
                root._issues = issues;
                root._state = "ok";
            } catch (e) {
                console.warn("GithubWidget: unparsable gh api output:", e.message);
                root._state = "error";
            }
        }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.xs

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: root._state === "ok" ? root.foreground : Theme.color.foregroundDim
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }

        MetaLabel {
            anchors.verticalCenter: parent.verticalCenter
            text: root._state === "ok"
                ? root._prs + "/" + root._issues
                : (root._state === "noauth" ? "NO AUTH" : "NO GH")
            color: root._state === "ok" ? root.foreground : Theme.color.foregroundDim
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: CompositorService.spawn(["xdg-open", "https://github.com/notifications"])
    }
}

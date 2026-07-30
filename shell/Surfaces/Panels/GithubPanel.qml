import QtQuick
import Quickshell.Io
import qs.Core
import qs.Components
import qs.Compositor

// GitHub panel (DESIGN.md §Panels, M13 Task 3): the popout behind
// GithubWidget's bar cell — two ledger sections, "PULL REQUESTS / n" then
// "ISSUES / n", each row a title plus dimmed repo slug, click spawns
// xdg-open on the row's url and closes the panel. The single `gh api
// graphql` poll lives HERE, not in the widget (the one deliberate deviation
// from the M13 plan's wording): `panel open github` over IPC must render
// honestly even when bar.layout never names the github widget, and a
// widget-owned poll would leave this surface permanently empty in that
// case. The widget stays the opt-in switch for background polling
// (pollEnabled below, flipped on from its Component.onCompleted — never
// unset, a mid-session layout edit that drops the widget just leaves the
// timer running until restart); opening the panel always re-polls, which is
// also what makes the no-widget IPC path work. Honest states, keyed off
// the sh wrapper's exit code exactly as the widget's poll always was:
// `gh` missing (exit 127) or any other failure/unparsable output renders a
// dim NO GH cell, gh's documented authentication exit code 4 renders NO
// AUTH, pre-first-answer renders LOADING (a poll is genuinely in flight —
// open always fires one), and an empty list renders a dim NONE row under
// its section header — never stale rows, never invented ones.
Panel {
    id: root

    panelTitle: "GITHUB"
    panelWidth: 380

    // Flipped true by GithubWidget when bar.layout actually names it — the
    // widget is opt-in precisely so users who never asked for it don't get
    // background `gh` network calls, and the panel honors the same opt-in.
    property bool pollEnabled: false

    // "unknown" (pre-first-answer) | "missing" | "noauth" | "error" | "ok"
    // — `state` itself is Item's built-in state-machine property, hence the
    // prefix. Read by GithubWidget for its counts cell and `shown` logic.
    property string pollState: "unknown"
    property int prCount: 0
    property int issueCount: 0
    // Arrays of {title, url, repo} parsed from the poll's first 15 search
    // nodes per list.
    property var prRows: []
    property var issueRows: []

    readonly property int _interval: {
        var v = Config.get("github.intervalMs", 300000);
        return (typeof v === "number" && v > 0) ? v : 300000;
    }

    function _poll() {
        if (proc.running)
            return;
        proc.running = true;
    }

    function _parseRows(nodes) {
        var rows = [];
        if (!Array.isArray(nodes))
            return rows;
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i];
            if (!n || typeof n.title !== "string" || typeof n.url !== "string")
                continue;
            rows.push({
                title: n.title,
                url: n.url,
                repo: (n.repository && typeof n.repository.nameWithOwner === "string") ? n.repository.nameWithOwner : ""
            });
        }
        return rows;
    }

    onPollEnabledChanged: if (root.pollEnabled) root._poll()
    onIsOpenChanged: if (root.isOpen) root._poll()

    Timer {
        interval: root._interval
        running: root.pollEnabled
        repeat: true
        onTriggered: root._poll()
    }

    Process {
        id: proc
        command: ["sh", "-c", "command -v gh >/dev/null 2>&1 || exit 127; exec gh api graphql -f query='{ prs: search(query: \"is:open is:pr author:@me\", type: ISSUE, first: 15) { issueCount nodes { ... on PullRequest { title url repository { nameWithOwner } } } } issues: search(query: \"is:open is:issue assignee:@me\", type: ISSUE, first: 15) { issueCount nodes { ... on Issue { title url repository { nameWithOwner } } } } }'"]
        stdout: StdioCollector {
            id: collector
        }
        onExited: exitCode => {
            if (exitCode === 127) {
                root.pollState = "missing";
                return;
            }
            if (exitCode === 4) {
                root.pollState = "noauth";
                return;
            }
            if (exitCode !== 0) {
                root.pollState = "error";
                return;
            }
            try {
                var d = JSON.parse(collector.text);
                var prs = d.data.prs.issueCount;
                var issues = d.data.issues.issueCount;
                if (typeof prs !== "number" || typeof issues !== "number")
                    throw new Error("counts missing");
                root.prCount = prs;
                root.issueCount = issues;
                root.prRows = root._parseRows(d.data.prs.nodes);
                root.issueRows = root._parseRows(d.data.issues.nodes);
                root.pollState = "ok";
            } catch (e) {
                console.warn("GithubPanel: unparsable gh api output:", e.message);
                root.pollState = "error";
            }
        }
    }

    Cell {
        visible: root.pollState === "unknown"
        width: parent.width

        MetaLabel { text: "LOADING" }
    }

    Cell {
        visible: root.pollState === "missing" || root.pollState === "error"
        width: parent.width

        MetaLabel { text: "NO GH" }
    }

    Cell {
        visible: root.pollState === "noauth"
        width: parent.width

        MetaLabel { text: "NO AUTH" }
    }

    Component {
        id: itemRow

        Cell {
            id: rowCell
            required property var modelData
            width: parent.width
            hovered: rowArea.containsMouse

            Column {
                width: parent.width
                spacing: Theme.spacing.xs

                Text {
                    width: parent.width
                    text: rowCell.modelData.title
                    color: rowCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.body
                    elide: Text.ElideRight
                }

                Text {
                    visible: rowCell.modelData.repo !== ""
                    width: parent.width
                    text: rowCell.modelData.repo
                    color: Theme.color.foregroundDim
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.caption
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    CompositorService.spawn(["xdg-open", rowCell.modelData.url]);
                    root.close();
                }
            }
        }
    }

    Cell {
        visible: root.pollState === "ok"
        width: parent.width

        MetaLabel { text: "PULL REQUESTS / " + root.prCount }
    }

    Repeater {
        model: root.pollState === "ok" ? root.prRows : []
        delegate: itemRow
    }

    Cell {
        visible: root.pollState === "ok" && root.prRows.length === 0
        width: parent.width

        MetaLabel { text: "NONE" }
    }

    Cell {
        visible: root.pollState === "ok"
        width: parent.width

        MetaLabel { text: "ISSUES / " + root.issueCount }
    }

    Repeater {
        model: root.pollState === "ok" ? root.issueRows : []
        delegate: itemRow
    }

    Cell {
        visible: root.pollState === "ok" && root.issueRows.length === 0
        width: parent.width

        MetaLabel { text: "NONE" }
    }
}

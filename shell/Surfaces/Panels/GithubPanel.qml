import QtQuick
import Quickshell.Io
import qs.Core
import qs.Components
import qs.Compositor
import qs.Services

// GitHub panel (DESIGN.md §3 "Panel", spec "Panels"): the popout behind
// GithubWidget's bar cell. A hero promoting the signed-in account and the
// total awaiting it, then `PULL REQUESTS (n)` and `ISSUES (n)` sections of
// `Cell` rows, each carrying the repo slug in mono over the title in sans.
//
// Keyboard (spec "Keyboard model"): the cursor spans both lists in one
// numeric space, pull requests first, and Enter opens the row's url through
// xdg-open and closes the panel, the same thing a click on it does. There is
// no per-row dismiss on this surface, so `x` is unbound.
//
// The single `gh api graphql` poll lives HERE, not in the widget (the one
// deliberate deviation from the M13 plan's wording): `panel open github`
// over IPC must render honestly even when bar.layout never names the github
// widget, and a widget-owned poll would leave this surface permanently empty
// in that case. The widget stays the opt-in switch for background polling
// (pollEnabled below, flipped on from its Component.onCompleted, never
// unset, so a mid-session layout edit that drops the widget just leaves the
// timer running until restart); opening the panel always re-polls, which is
// also what makes the no-widget IPC path work. Honest states, keyed off
// the sh wrapper's exit code exactly as the widget's poll always was:
// `gh` missing (exit 127) or any other failure/unparsable output renders a
// dim NO GH cell, gh's documented authentication exit code 4 renders NO
// AUTH, pre-first-answer renders LOADING (a poll is genuinely in flight,
// open always fires one), and an empty list renders a dim NONE row under
// its section header, never stale rows and never invented ones.
Panel {
    id: root

    panelIcon: "git-branch"
    panelTitle: "GitHub"
    panelWidth: Theme.space.popupWidthDefault

    // Flipped true by GithubWidget when bar.layout actually names it: the
    // widget is opt-in precisely so users who never asked for it don't get
    // background `gh` network calls, and the panel honors the same opt-in.
    property bool pollEnabled: false

    // "unknown" (pre-first-answer) | "missing" | "noauth" | "error" | "ok".
    // `state` itself is Item's built-in state-machine property, hence the
    // prefix. Read by GithubWidget for its counts cell and `shown` logic.
    property string pollState: "unknown"
    property int prCount: 0
    property int issueCount: 0
    // Arrays of {title, url, repo} parsed from the poll's first 15 search
    // nodes per list.
    property var prRows: []
    property var issueRows: []
    // The authenticated account itself (the hero's subject): "" until a poll
    // answers, never a guess at who's signed in.
    property string viewerLogin: ""

    // The cursor spans both lists at once, pull requests first, so each row
    // carries the index Panel addresses it by rather than the Repeater's own
    // list-local one.
    readonly property var _prRowModel: (root.pollState === "ok" ? root.prRows : []).map(function (row, i) {
        return { row: row, cursor: i };
    })
    readonly property var _issueRowModel: (root.pollState === "ok" ? root.issueRows : []).map(function (row, i) {
        return { row: row, cursor: (root.pollState === "ok" ? root.prRows.length : 0) + i };
    })

    cursorCount: root._prRowModel.length + root._issueRowModel.length

    onCursorActivated: index => {
        var rows = root._prRowModel.concat(root._issueRowModel);
        if (index >= 0 && index < rows.length)
            root._openRow(rows[index].row);
    }

    function _openRow(row) {
        if (!row)
            return;
        CompositorService.spawn(["xdg-open", row.url]);
        root.close();
    }

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
    onIsOpenChanged: {
        if (!root.isOpen)
            return;
        root._poll();
        root.cursorIndex = 0;
    }

    Timer {
        interval: root._interval
        running: root.pollEnabled
        repeat: true
        onTriggered: root._poll()
    }

    // Refresh the moment the network comes back rather than waiting out the
    // rest of a 5-minute tick on a NO GH cell (ConnectivityService).
    Connections {
        target: ConnectivityService
        function onReconnected() {
            if (root.pollEnabled || root.isOpen)
                root._poll();
        }
    }

    Process {
        id: proc
        command: ["sh", "-c", "command -v gh >/dev/null 2>&1 || exit 127; exec gh api graphql -f query='{ viewer { login } prs: search(query: \"is:open is:pr author:@me\", type: ISSUE, first: 15) { issueCount nodes { ... on PullRequest { title url repository { nameWithOwner } } } } issues: search(query: \"is:open is:issue assignee:@me\", type: ISSUE, first: 15) { issueCount nodes { ... on Issue { title url repository { nameWithOwner } } } } }'"]
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
                root.viewerLogin = (d.data.viewer && typeof d.data.viewer.login === "string") ? d.data.viewer.login : "";
                root.pollState = "ok";
            } catch (e) {
                console.warn("GithubPanel: unparsable gh api output:", e.message);
                root.pollState = "error";
            }
        }
    }

    SectionLabel {
        visible: root.pollState === "unknown"
        leftPadding: Theme.space.controlPaddingX
        text: "LOADING"
    }

    SectionLabel {
        visible: root.pollState === "missing" || root.pollState === "error"
        leftPadding: Theme.space.controlPaddingX
        text: "NO GH"
    }

    SectionLabel {
        visible: root.pollState === "noauth"
        leftPadding: Theme.space.controlPaddingX
        text: "NO AUTH"
    }

    // The panel's own subject: the signed-in account, and how many things
    // await it. The two sections below still carry their own breakdown (PRs
    // vs. issues); this only promotes the total.
    PanelHero {
        id: hero
        visible: root.pollState === "ok"
        width: parent.width
        title: root.viewerLogin !== "" ? root.viewerLogin : "GitHub"
        meta: "Open items"
        readout: String(root.prCount + root.issueCount)

        leading: Component {
            Icon {
                name: "git-branch"
                size: Theme.fontSize.heading
                color: hero.foreground
            }
        }
    }

    Component {
        id: itemRow

        Cell {
            id: rowCell
            required property var modelData
            width: parent.width

            readonly property var _row: rowCell.modelData.row
            readonly property int _cursorIndex: rowCell.modelData.cursor

            cursor: root.cursorActive && root.cursorIndex === rowCell._cursorIndex

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                // A repo slug is an identifier, so it takes the mono face;
                // the title beside it is prose (spec "Type").
                Text {
                    visible: rowCell._row.repo !== ""
                    width: parent.width
                    text: rowCell._row.repo
                    color: rowCell.dimForeground
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSize.caption
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: rowCell._row.title
                    color: rowCell.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                    elide: Text.ElideRight
                }
            }

            interactive: true
            onContainsPointerChanged: if (rowCell.containsPointer) {
                root.cursorActive = true;
                root.cursorIndex = rowCell._cursorIndex;
            }
            onClicked: root._openRow(rowCell._row)
        }
    }

    Column {
        width: parent.width
        visible: root.pollState === "ok"
        spacing: Theme.space.rowGap

        SectionLabel {
            leftPadding: Theme.space.controlPaddingX
            text: "PULL REQUESTS"
            count: root.prCount
        }

        SectionLabel {
            visible: root.prRows.length === 0
            leftPadding: Theme.space.controlPaddingX
            text: "NONE"
        }

        Repeater {
            model: root._prRowModel
            delegate: itemRow
        }
    }

    Column {
        width: parent.width
        visible: root.pollState === "ok"
        spacing: Theme.space.rowGap

        SectionLabel {
            leftPadding: Theme.space.controlPaddingX
            text: "ISSUES"
            count: root.issueCount
        }

        SectionLabel {
            visible: root.issueRows.length === 0
            leftPadding: Theme.space.controlPaddingX
            text: "NONE"
        }

        Repeater {
            model: root._issueRowModel
            delegate: itemRow
        }
    }
}

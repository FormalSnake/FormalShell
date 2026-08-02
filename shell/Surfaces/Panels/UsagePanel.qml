import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Components
import "../../Usage/usage.js" as Usage

// AI usage panel (DESIGN.md §Panels, M14 Task 7): the popout behind
// UsageWidget's bar cell — a CLAUDE section (Anthropic OAuth usage) and a
// CODEX section (`codex app-server` JSON-RPC), each an uppercase tier meta
// row followed by one row per rate-limit window (label, percent, a
// full-width flat accent/urgent fill track per DESIGN.md's slider idiom,
// dim RESETS meta). GithubPanel's poll-in-panel pattern verbatim: the poll
// lives HERE, not in the widget, so `panel open usage` renders honestly
// even when bar.layout never names the usage widget (the widget stays the
// opt-in switch for background polling; opening the panel always
// re-polls). `usage.claude`/`usage.codex` (settings.json, default true)
// independently gate each provider's section and polling entirely — a
// disabled provider renders no section at all, not an honest-empty one.
//
// Claude leg: `~/.claude/.credentials.json`'s `.claudeAiOauth.accessToken`
// (never logged, never exposed on any IPC/debug surface — Constraints)
// authenticates a GET against Anthropic's OAuth usage endpoint
// (`api.anthropic.com/api/oauth/usage`, headers `Authorization: Bearer
// <token>` + `anthropic-beta: oauth-2025-04-20` + `Accept:
// application/json` — WeatherPanel's own XMLHttpRequest idiom). Missing
// credentials, an empty token, or an expired one all render an honest `NO
// AUTH` state rather than probing at all.
//
// Codex leg: `codex -s read-only -a untrusted app-server` speaks
// newline-delimited JSON-RPC over stdin/stdout (verified against
// `~/Developer/omarchy/shell/plugins/model-usage/scripts/
// codex_usage_scanner.py`'s `rpc_request()` — one JSON object per line, no
// Content-Length framing) via a real quickshell Process
// (`Process.write()`/`stdinEnabled`, the same stdin idiom NetworkPanel's
// enterprise-EAP flow already uses, including its "check the binary exists
// before ever touching stdin" `command -v` guard). Replies are matched by
// their JSON-RPC `id` rather than assumed in order, mirroring the
// scanner's own id-checked `rpc_request()` rather than blind sequencing.
// `codex` missing from PATH (`sh -c`'s `command -v` guard, exit 127)
// renders `NO CODEX`; any RPC-level failure (timeout, malformed reply,
// missing fields) renders `ERROR` rather than a fake number — this repo has
// no way to exercise a real codex binary in the VM rig, so this leg's
// correctness rides on usage.js's own parser tests plus qmllint, stated
// honestly in the commit, the same allowance BluetoothPanel's pairing flow
// already took for its own VM-unreachable paths.
Panel {
    id: root

    panelTitle: "USAGE"
    panelWidth: 300

    // Flipped true by UsageWidget when bar.layout actually names it — see
    // GithubWidget's own header for why background polling stays opt-in.
    property bool pollEnabled: false

    readonly property bool claudeEnabled: Config.get("usage.claude", true) === true
    readonly property bool codexEnabled: Config.get("usage.codex", true) === true

    readonly property int _interval: {
        var v = Config.get("usage.intervalMs", 900000);
        return (typeof v === "number" && v > 0) ? v : 900000;
    }

    // "unknown" (pre-first-answer) | "noauth" | "loading" | "error" | "ok"
    property string claudeState: "unknown"
    property string claudeTier: ""
    property var claudeRows: []
    property string _claudeAccessToken: ""

    // "unknown" | "missing" | "loading" | "error" | "ok"
    property string codexState: "unknown"
    property string codexTier: ""
    property var codexRows: []
    property string _codexPlanType: ""

    // The single number UsageWidget's bar cell shows — the highest
    // utilization across every currently-`ok` window from every enabled
    // provider; -1 when neither provider has a real percentage to show.
    readonly property real worstPercent: {
        var w = -1;
        if (root.claudeEnabled && root.claudeState === "ok")
            for (var i = 0; i < root.claudeRows.length; i++)
                w = Math.max(w, root.claudeRows[i].percent);
        if (root.codexEnabled && root.codexState === "ok")
            for (var j = 0; j < root.codexRows.length; j++)
                w = Math.max(w, root.codexRows[j].percent);
        return w;
    }

    function claudeStatusText() {
        switch (root.claudeState) {
        case "noauth": return "NO AUTH";
        case "loading": return "LOADING";
        case "error": return "ERROR";
        default: return "";
        }
    }

    function codexStatusText() {
        switch (root.codexState) {
        case "missing": return "NO CODEX";
        case "loading": return "LOADING";
        case "error": return "ERROR";
        default: return "";
        }
    }

    // UsageWidget's fallback cell text when worstPercent has nothing to
    // show: whichever enabled, unsettled provider's honest state, Claude
    // first (the owner's primary tool).
    readonly property string statusLabel: {
        if (root.claudeEnabled && root.claudeState !== "ok" && root.claudeState !== "unknown")
            return root.claudeStatusText();
        if (root.codexEnabled && root.codexState !== "ok" && root.codexState !== "unknown")
            return root.codexStatusText();
        return "";
    }

    function _poll() {
        if (root.claudeEnabled)
            credentialsFile.reload();
        else
            root.claudeState = "unknown";
        if (root.codexEnabled)
            root._pollCodex();
        else
            root.codexState = "unknown";
    }

    onPollEnabledChanged: if (root.pollEnabled) root._poll()
    onIsOpenChanged: if (root.isOpen) root._poll()

    Timer {
        interval: root._interval
        running: root.pollEnabled
        repeat: true
        onTriggered: root._poll()
    }

    // ---- Claude leg ----

    FileView {
        id: credentialsFile
        printErrors: false
        path: (Quickshell.env("HOME") || "") + "/.claude/.credentials.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._applyCredentials(text())
        onLoadFailed: error => {
            root.claudeState = "noauth";
            root._claudeAccessToken = "";
            root.claudeRows = [];
        }
    }

    function _applyCredentials(text) {
        var parsed = Usage.parseCredentials(text);
        if (!parsed.ok) {
            root.claudeState = "noauth";
            root._claudeAccessToken = "";
            root.claudeRows = [];
            return;
        }
        root._claudeAccessToken = parsed.accessToken;
        root.claudeTier = Usage.tierLabel(parsed.subscriptionType, parsed.rateLimitTier);
        if (Usage.credentialsExpired(parsed.expiresAtMs, Date.now())) {
            root.claudeState = "noauth";
            root._claudeAccessToken = "";
            root.claudeRows = [];
            return;
        }
        root._probeClaudeUsage();
    }

    function _probeClaudeUsage() {
        if (root._claudeAccessToken === "") {
            root.claudeState = "noauth";
            return;
        }
        root.claudeState = "loading";
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.anthropic.com/api/oauth/usage");
        xhr.setRequestHeader("Authorization", "Bearer " + root._claudeAccessToken);
        xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20");
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status < 200 || xhr.status >= 300) {
                root.claudeState = "error";
                return;
            }
            var parsed = Usage.parseUsage(xhr.responseText);
            if (!parsed.ok) {
                root.claudeState = "error";
                return;
            }
            root.claudeRows = parsed.rows;
            root.claudeState = "ok";
        };
        xhr.send();
    }

    // ---- Codex leg ----

    function _pollCodex() {
        if (codexProc.running)
            return;
        root.codexTier = "";
        root._codexPlanType = "";
        root.codexRows = [];
        codexProc.running = true;
    }

    function _handleCodexLine(line) {
        if (!line || line.trim() === "")
            return;
        var msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!msg || typeof msg !== "object" || msg.id === undefined)
            return;

        if (msg.id === 1) {
            codexProc.write(JSON.stringify({ method: "initialized", params: {} }) + "\n");
            codexProc.write(JSON.stringify({ id: 2, method: "account/read", params: {} }) + "\n");
        } else if (msg.id === 2) {
            var account = Usage.parseCodexAccount(line);
            if (account.ok)
                root._codexPlanType = account.planType;
            codexProc.write(JSON.stringify({ id: 3, method: "account/rateLimits/read", params: {} }) + "\n");
        } else if (msg.id === 3) {
            codexTimeout.stop();
            var limits = Usage.parseCodexRateLimits(line);
            if (!limits.ok) {
                root.codexState = "error";
            } else {
                root.codexTier = limits.planType || root._codexPlanType;
                root.codexRows = limits.rows;
                root.codexState = "ok";
            }
            codexProc.running = false;
        }
    }

    // Safety net for a codex binary that starts, authenticates, but never
    // replies to all three requests (a hung app-server, a permissions
    // prompt with nothing on the other end to answer it) — clears a stuck
    // "loading" state to an honest "ERROR" instead of forever.
    Timer {
        id: codexTimeout
        interval: 20000
        repeat: false
        onTriggered: {
            if (root.codexState !== "loading")
                return;
            root.codexState = "error";
            codexProc.running = false;
        }
    }

    Process {
        id: codexProc
        stdinEnabled: true
        command: ["sh", "-c", "command -v codex >/dev/null 2>&1 || exit 127; exec codex -s read-only -a untrusted app-server"]

        stdout: SplitParser {
            onRead: line => root._handleCodexLine(line)
        }

        onStarted: {
            root.codexState = "loading";
            codexTimeout.restart();
            codexProc.write(JSON.stringify({ id: 1, method: "initialize", params: { clientInfo: { name: "formalshell", version: "1" } } }) + "\n");
        }

        onExited: function (exitCode) {
            codexTimeout.stop();
            if (root.codexState === "ok")
                return;
            root.codexState = exitCode === 127 ? "missing" : "error";
        }
    }

    // ---- Shared row rendering ----

    Component {
        id: usageRow

        Cell {
            id: rowCell
            required property var modelData
            width: parent.width
            readonly property bool _urgent: rowCell.modelData.percent >= 0.9

            Column {
                width: parent.width
                spacing: Theme.spacing.xs

                MetaLabel { text: rowCell.modelData.label }

                Text {
                    text: Math.round(rowCell.modelData.percent * 100) + "%"
                    color: rowCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.body
                }

                Rectangle {
                    width: parent.width
                    height: 6
                    color: Theme.color.rule

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, rowCell.modelData.percent))
                        height: parent.height
                        color: rowCell._urgent ? Theme.color.urgent : Theme.color.accent
                    }
                }

                MetaLabel {
                    visible: rowCell.modelData.resetsAt !== ""
                    text: Usage.formatReset(Date.now(), rowCell.modelData.resetsAt)
                }
            }
        }
    }

    // ---- CLAUDE section ----

    Cell {
        visible: root.claudeEnabled
        width: parent.width

        MetaLabel { text: "CLAUDE" + (root.claudeTier !== "" ? " / " + root.claudeTier : "") }
    }

    Cell {
        visible: root.claudeEnabled && root.claudeState !== "ok"
        width: parent.width

        MetaLabel { text: root.claudeState === "unknown" ? "LOADING" : root.claudeStatusText() }
    }

    Repeater {
        model: root.claudeEnabled && root.claudeState === "ok" ? root.claudeRows : []
        delegate: usageRow
    }

    // ---- CODEX section ----

    Cell {
        visible: root.codexEnabled
        width: parent.width

        MetaLabel { text: "CODEX" + (root.codexTier !== "" ? " / " + root.codexTier : "") }
    }

    Cell {
        visible: root.codexEnabled && root.codexState !== "ok"
        width: parent.width

        MetaLabel { text: root.codexState === "unknown" ? "LOADING" : root.codexStatusText() }
    }

    Repeater {
        model: root.codexEnabled && root.codexState === "ok" ? root.codexRows : []
        delegate: usageRow
    }
}

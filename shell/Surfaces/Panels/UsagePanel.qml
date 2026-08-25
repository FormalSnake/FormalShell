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
// credentials or an empty token render an honest `NO AUTH`.
//
// An *expired* access token is a third state, not `NO AUTH`: the file's
// accessToken lives ~12h while its refreshToken lives ~10d, and only a Claude
// Code run refreshes the pair on disk, so a machine that hasn't run `claude`
// today is still fully logged in with a token this shell can't use. That
// renders `STALE` and points at the fix. The shell deliberately does NOT
// redeem the refresh token itself: Anthropic rotates it on use, so redeeming
// it here would invalidate the copy Claude Code still holds and log the owner
// out of their own CLI.
//
// It asks the CLI to do it instead, so the leg heals without anyone opening a
// terminal: a stale leg (and the bar cell's own click) spawns `claude auth
// status --json`, which refreshes the pair on disk under Claude Code's own
// ownership. That invocation was picked by proxy-tracing every host claude
// 2.1.224 connects to: with an expired accessToken it reaches the OAuth token
// endpoint (platform.claude.com), with a live one it opens no connection at
// all, and neither case calls a model, so refreshing costs no usage and a
// needless call costs nothing. Its stdout is dropped unread (it carries
// account identity, not usage) and only the exit code picks the panel's hint,
// via `refreshStateForExit`. Nothing about the leg's own state is taken from
// the CLI's word: the refreshed file arrives through `credentialsFile`'s watch
// like any other write, and the server settles the state as it always did.
//
// A token that expires between two polls would otherwise sit `STALE` for up to
// `usage.intervalMs`, so `_applyCredentials` also arms a one-shot at the
// token's own expiry to re-poll (and therefore refresh) right when it lapses.
//
// The local `expiresAt` is advisory — a skewed clock or a changed field
// meaning must not be able to hide real usage numbers — so a probe fires
// whenever a token exists at all and the server's own verdict settles the
// state: 2xx wins outright, 401/403 falls back to `STALE` (refresh token
// present) or `NO AUTH` (none), anything else is `ERROR`. `expiresAt` only
// picks the label shown while that probe is in flight.
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
    panelWidth: Theme.space.popupWidthDefault

    // Flipped true by UsageWidget when bar.layout actually names it — see
    // GithubWidget's own header for why background polling stays opt-in.
    property bool pollEnabled: false

    readonly property bool claudeEnabled: Config.get("usage.claude", true) === true
    readonly property bool codexEnabled: Config.get("usage.codex", true) === true

    readonly property int _interval: {
        var v = Config.get("usage.intervalMs", 900000);
        return (typeof v === "number" && v > 0) ? v : 900000;
    }

    // The single row nearest its limit across every ENABLED provider, or null
    // before any provider has answered. Only "ok" providers contribute: a
    // failed or disabled leg has no windows to rank, and ranking a leg that is
    // merely still loading would make the headline jump as the slower one
    // lands.
    readonly property var _peakRow: {
        var rows = [];
        if (root.claudeEnabled && root.claudeState === "ok")
            rows = rows.concat(root.claudeRows);
        if (root.codexEnabled && root.codexState === "ok")
            rows = rows.concat(root.codexRows);
        var peak = null;
        for (var i = 0; i < rows.length; i++) {
            if (!rows[i] || !isFinite(Number(rows[i].percent)))
                continue;
            if (!peak || Number(rows[i].percent) > Number(peak.percent))
                peak = rows[i];
        }
        return peak;
    }

    // "unknown" (pre-first-answer) | "noauth" | "stale" | "loading" | "error" | "ok"
    property string claudeState: "unknown"
    property string claudeTier: ""
    property var claudeRows: []
    property string _claudeAccessToken: ""
    property bool _claudeHasRefreshToken: false

    // How the last `claude auth status --json` run ended (see the header):
    // "idle" (never run) | "running" | "ok" | "nocli" | "failed"
    property string claudeRefreshState: "idle"
    property real _lastRefreshMs: 0
    readonly property int _refreshCooldownMs: 60000

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
        case "stale": return "STALE";
        case "loading": return "LOADING";
        case "error": return "ERROR";
        default: return "";
        }
    }

    // The bar cell only has room for the status word, so the actionable half
    // of the STALE state ("errors say how to fix") is rendered here, where
    // there's width for it, and follows the refresh attempt as it runs.
    function claudeHintText() {
        if (root.claudeState === "unknown")
            return "LOADING";
        if (root.claudeState !== "stale")
            return root.claudeStatusText();
        return "STALE / " + Usage.refreshHint(root.claudeRefreshState);
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
        if (root.claudeEnabled) {
            root._credentialsRetries = 0;
            credentialsFile.reload();
        } else {
            root.claudeState = "unknown";
        }
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
            root._claudeHasRefreshToken = false;
            root.claudeRows = [];
            if (error === FileViewError.FileNotFound && root.claudeEnabled && root._credentialsRetries < root._maxCredentialsRetries) {
                root._credentialsRetries++;
                credentialsRewatch.restart();
            }
        }
    }

    // Config.qml's own rewatch idiom, for the same reason: Claude Code
    // rewrites `.credentials.json` by rename, which both unhooks the watch
    // from the replaced inode and can land a poll on the gap between unlink
    // and link. Without this a one-frame miss reads as NO AUTH until the next
    // `usage.intervalMs` tick a quarter of an hour later.
    //
    // BOUNDED, unlike Config.qml's and Theme.qml's copies of this idiom: those
    // terminate because the shell writes settings.json/theme.json itself, so
    // the file always eventually appears. Nothing here ever creates
    // `.credentials.json`, so an unbounded retry would be a permanent 3.3Hz
    // stat loop on every machine without Claude Code installed — including the
    // VM smoke rig, and the honest NO AUTH state itself. A rename gap closes in
    // milliseconds, so a short burst covers it; after that the normal poll and
    // the FileView's own watch are what pick the file up.
    property int _credentialsRetries: 0
    readonly property int _maxCredentialsRetries: 3

    Timer {
        id: credentialsRewatch
        interval: 300
        onTriggered: credentialsFile.reload()
    }

    function _applyCredentials(text) {
        root._credentialsRetries = 0;
        var parsed = Usage.parseCredentials(text);
        if (!parsed.ok || parsed.accessToken === "") {
            claudeExpiry.stop();
            root.claudeState = "noauth";
            root._claudeAccessToken = "";
            root._claudeHasRefreshToken = false;
            root.claudeRows = [];
            return;
        }
        root._claudeAccessToken = parsed.accessToken;
        root._claudeHasRefreshToken = parsed.hasRefreshToken;
        root.claudeTier = Usage.tierLabel(parsed.subscriptionType, parsed.rateLimitTier);
        root._armClaudeExpiry(parsed.expiresAtMs);
        root._probeClaudeUsage(Usage.credentialsExpired(parsed.expiresAtMs, Date.now()));
    }

    // One-shot re-poll the moment the token lapses, so the leg refreshes itself
    // then instead of sitting STALE until the next `usage.intervalMs` tick. The
    // 24h ceiling keeps a nonsense far-future expiry (or a clock skewed by
    // days) out of Timer's int millisecond interval; the normal poll covers
    // that case on its own.
    function _armClaudeExpiry(expiresAtMs) {
        var untilExpiry = expiresAtMs - Date.now();
        if (expiresAtMs <= 0 || untilExpiry <= 0 || untilExpiry > 86400000) {
            claudeExpiry.stop();
            return;
        }
        claudeExpiry.interval = untilExpiry + 2000;
        claudeExpiry.restart();
    }

    Timer {
        id: claudeExpiry
        repeat: false
        onTriggered: if (root.claudeEnabled) root._poll()
    }

    // `expiredLocally` only picks the in-flight label (STALE reads truer than
    // LOADING when the file already says the token is dead) — the reply below
    // settles the state either way.
    function _probeClaudeUsage(expiredLocally) {
        if (root._claudeAccessToken === "") {
            root.claudeState = "noauth";
            return;
        }
        root.claudeState = expiredLocally ? "stale" : "loading";
        if (expiredLocally)
            root.refreshClaudeToken(false);
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.anthropic.com/api/oauth/usage");
        xhr.setRequestHeader("Authorization", "Bearer " + root._claudeAccessToken);
        xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20");
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status === 401 || xhr.status === 403) {
                root.claudeState = root._claudeHasRefreshToken ? "stale" : "noauth";
                root.claudeRows = [];
                if (root._claudeHasRefreshToken)
                    root.refreshClaudeToken(false);
                return;
            }
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

    // ---- Claude token refresh ----

    // Hand the refresh to Claude Code (see the header). Bounded by a cooldown
    // so a refresh that can never succeed (logged out, offline) still can't
    // spawn a process per poll, per panel open, or per click; `force` is the
    // bar cell's own click, an explicit ask that skips the cooldown.
    function refreshClaudeToken(force) {
        if (!root.claudeEnabled || refreshProc.running)
            return;
        var now = Date.now();
        if (!force && root._lastRefreshMs > 0 && (now - root._lastRefreshMs) < root._refreshCooldownMs)
            return;
        root._lastRefreshMs = now;
        refreshProc.running = true;
    }

    Process {
        id: refreshProc
        // stdout is dropped at the shell rather than parsed: it answers with
        // account identity (email, org), never usage, and the exit code alone
        // is what picks the hint.
        command: ["sh", "-c", "command -v claude >/dev/null 2>&1 || exit 127; exec claude auth status --json >/dev/null 2>&1"]

        onStarted: {
            root.claudeRefreshState = "running";
            refreshTimeout.restart();
        }

        // A refreshed file usually lands via credentialsFile's own watch before
        // this fires; the reload covers the case where it doesn't (an atomic
        // rename the watch missed), and costs one stat when nothing changed.
        onExited: function (exitCode) {
            refreshTimeout.stop();
            if (root.claudeRefreshState === "running")
                root.claudeRefreshState = Usage.refreshStateForExit(exitCode);
            root._credentialsRetries = 0;
            credentialsFile.reload();
        }
    }

    // codexTimeout's own safety net, for the same reason: a `claude` that
    // starts and then hangs (captive-portal network, a login prompt with
    // nothing on the other end to answer it) must not pin the leg in
    // REFRESHING forever.
    Timer {
        id: refreshTimeout
        interval: 30000
        repeat: false
        onTriggered: {
            if (root.claudeRefreshState !== "running")
                return;
            root.claudeRefreshState = "failed";
            refreshProc.running = false;
        }
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
                spacing: Theme.space.xxs

                MetaLabel { text: rowCell.modelData.label }

                Text {
                    text: Math.round(rowCell.modelData.percent * 100) + "%"
                    color: rowCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }

                DitherFill {
                    width: parent.width
                    height: Theme.space.trackThickness

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, rowCell.modelData.percent))
                        height: parent.height
                        color: rowCell._urgent ? Theme.color.destructive : Theme.color.primary
                    }
                }

                MetaLabel {
                    visible: rowCell.modelData.resetsAt !== ""
                    text: Usage.formatReset(Date.now(), rowCell.modelData.resetsAt)
                }
            }
        }
    }

    // The panel's headline: of every rate window on show, the one closest to
    // its limit, which is the question the panel gets opened to answer. The
    // sections below still list every window; this only promotes the worst.
    //
    // It names that window in the meta line rather than repeating the section
    // header, so the hero and the CLAUDE/CODEX headers below state different
    // facts instead of the same one twice.
    PanelHero {
        width: parent.width
        glyph: "󱚣"
        title: "Usage"
        meta: root._peakRow ? root._peakRow.label : (root.claudeEnabled ? "LOADING" : "DISABLED")
        readout: root._peakRow ? Math.round(root._peakRow.percent * 100) + "%" : ""
        rail: root._peakRow ? root._peakRow.percent : -1
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

        MetaLabel { text: root.claudeHintText() }
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

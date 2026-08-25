.pragma library

// Pure glue for the AI usage panel (M14 Task 7): credentials/response
// parsing for both providers, no Quickshell/XHR/Process access, so it's
// testable head-on (mirrors openmeteo.js). Shapes verified against
// Anthropic's OAuth usage endpoint and Codex's app-server JSON-RPC replies
// per the plan's research header, this file is an original
// reimplementation of that behavior, not ported from omarchy (read-
// reference only per CLAUDE.md's Reference repos section).

function _isObject(v) {
    return v !== null && typeof v === "object";
}

// ---- Claude (Anthropic OAuth) ----

// `~/.claude/.credentials.json`'s `.claudeAiOauth` object.
function parseCredentials(body) {
    var data;
    try {
        data = JSON.parse(body);
    } catch (e) {
        return { ok: false, error: "malformed_json" };
    }
    if (!_isObject(data))
        return { ok: false, error: "malformed_json" };

    var oauth = data.claudeAiOauth;
    if (!_isObject(oauth))
        return { ok: false, error: "missing_fields" };

    var accessToken = typeof oauth.accessToken === "string" ? oauth.accessToken : "";
    if (accessToken === "")
        return { ok: false, error: "missing_fields" };

    // The refresh token itself is never returned, only whether one is
    // present, which is all the caller needs to tell "logged out" apart from
    // "logged in, access token needs refreshing" (see credentialsExpired).
    return {
        ok: true,
        accessToken: accessToken,
        hasRefreshToken: typeof oauth.refreshToken === "string" && oauth.refreshToken !== "",
        expiresAtMs: _normalizeExpiresAtMs(oauth.expiresAt),
        subscriptionType: typeof oauth.subscriptionType === "string" ? oauth.subscriptionType : "",
        rateLimitTier: typeof oauth.rateLimitTier === "string" ? oauth.rateLimitTier : ""
    };
}

function _normalizeExpiresAtMs(value) {
    var n = Number(value);
    return (isFinite(n) && n > 0) ? n : 0;
}

// 0/absent expiresAtMs means the credentials carry no expiry info at all,
// not the same as "expired now".
//
// Claude Code's accessToken lives ~12h while its refreshToken lives ~10d, and
// only a Claude Code run refreshes the pair on disk. An expired accessToken
// therefore means "logged in, token needs refreshing", NOT "logged out", the
// caller renders those as different states. This is advisory only: the local
// clock decides which label shows while a probe is in flight, the server's own
// 401 decides the settled state.
function credentialsExpired(expiresAtMs, nowMs) {
    return expiresAtMs > 0 && expiresAtMs <= nowMs;
}

// GET https://api.anthropic.com/api/oauth/usage's body: a flat object whose
// keys are rate-limit windows, each shaped `{utilization, resets_at}`,
// `five_hour`, `seven_day`, and (2026-08-03) per-model keys like
// `seven_day_opus`/`seven_day_sonnet` that the endpoint adds without notice.
// Every such key is rendered, so a future bucket (e.g. a `fable` window)
// shows up the day the API adds it with zero code changes here.
function parseUsage(body) {
    var payload;
    try {
        payload = JSON.parse(body);
    } catch (e) {
        return { ok: false, error: "malformed_json" };
    }
    if (!_isObject(payload))
        return { ok: false, error: "malformed_json" };

    var keys = _rateWindowKeys(payload);
    if (keys.length === 0)
        return { ok: false, error: "missing_fields" };

    var buckets = keys.map(function (k) { return payload[k]; });
    var percentScale = _usesPercentScale(buckets);

    var rows = [];
    for (var i = 0; i < keys.length; i++) {
        var row = _usageRow(_bucketLabel(keys[i]), payload[keys[i]], percentScale);
        if (row)
            rows.push(row);
    }

    if (rows.length === 0)
        return { ok: false, error: "missing_fields" };
    return { ok: true, rows: rows };
}

// Every own key whose value looks like a rate window (an object carrying a
// `utilization` field), ordered `five_hour`, `seven_day`, then alphabetical
//, stable regardless of the source object's own key order.
function _rateWindowKeys(payload) {
    var candidates = [];
    for (var key in payload) {
        var value = payload[key];
        if (_isObject(value) && "utilization" in value)
            candidates.push(key);
    }

    var head = ["five_hour", "seven_day"].filter(function (k) { return candidates.indexOf(k) !== -1; });
    var rest = candidates.filter(function (k) { return head.indexOf(k) === -1; }).sort();
    return head.concat(rest);
}

// five_hour -> 5-HOUR, seven_day -> WEEKLY, seven_day_<x> -> WEEKLY <X>
// (covers seven_day_opus/seven_day_sonnet and any future per-model window),
// anything else -> uppercased with underscores turned to spaces.
function _bucketLabel(key) {
    if (key === "five_hour")
        return "5-HOUR";
    if (key === "seven_day")
        return "WEEKLY";
    if (key.indexOf("seven_day_") === 0)
        return "WEEKLY " + key.slice("seven_day_".length).replace(/_/g, " ").toUpperCase();
    return key.replace(/_/g, " ").toUpperCase();
}

// The endpoint has been observed to report both percent-scaled (37.0) and
// fraction-scaled (0.37) utilization; a payload containing any value >= 1
// is treated as percent-scaled across every bucket in it, so a session at
// 0% never gets misread as a fraction while a weekly bucket in the same
// response is percent-scaled.
function _usesPercentScale(buckets) {
    for (var i = 0; i < buckets.length; i++) {
        if (!buckets[i])
            continue;
        var n = Number(buckets[i].utilization);
        if (isFinite(n) && n >= 1)
            return true;
    }
    return false;
}

function _usageRow(label, bucket, percentScale) {
    if (!bucket || bucket.utilization === null || bucket.utilization === undefined)
        return null;
    var n = Number(bucket.utilization);
    if (!isFinite(n) || n < 0)
        return null;
    var percent = percentScale ? Math.min(1, n / 100) : Math.min(1, n);
    return {
        label: label,
        percent: percent,
        resetsAt: typeof bucket.resets_at === "string" ? bucket.resets_at : ""
    };
}

// `formatTier()` in omarchy's provider: a rateLimitTier of "max_20x" reads
// as "Max 20x"; otherwise fall back to a capitalized subscriptionType.
function tierLabel(subscriptionType, rateLimitTier) {
    if (rateLimitTier) {
        var m = /max_(\d+x)/i.exec(rateLimitTier);
        if (m)
            return "Max " + m[1];
    }
    return subscriptionType ? _capitalize(subscriptionType) : "";
}

function _capitalize(s) {
    return s.charAt(0).toUpperCase() + s.slice(1);
}

// A window label as body copy rather than as a section label. `_bucketLabel`
// answers uppercase because the panel's rows render it through
// `SectionLabel`, and only a section label uppercases (DESIGN.md §5), so the
// hero's own sentence-case meta line reads it back through this.
function sentenceLabel(label) {
    var s = String(label === undefined || label === null ? "" : label).toLowerCase();
    return s === "" ? "" : _capitalize(s);
}

// "RESETS 2H 14M" / "RESETS 1D 3H" / "RESETS NOW" / "" for no timestamp.
function formatReset(nowMs, resetsAtIso) {
    if (!resetsAtIso)
        return "";
    var reset = new Date(resetsAtIso).getTime();
    if (!isFinite(reset))
        return "";
    var diffMs = reset - nowMs;
    if (diffMs <= 0)
        return "RESETS NOW";

    var totalMins = Math.floor(diffMs / 60000);
    var hours = Math.floor(totalMins / 60);
    var mins = totalMins % 60;
    if (hours > 24)
        return "RESETS " + Math.floor(hours / 24) + "D " + (hours % 24) + "H";
    if (hours > 0)
        return "RESETS " + hours + "H " + mins + "M";
    return "RESETS " + mins + "M";
}

// ---- Claude token refresh (`claude auth status --json`) ----

// How the panel's refresh helper ended, from its exit code. 127 is the
// `command -v claude` guard's own code (no CLI installed at all); any other
// non-zero is the CLI itself answering that it cannot help: logged out, dead
// refresh token, no network.
function refreshStateForExit(exitCode) {
    if (exitCode === 0)
        return "ok";
    if (exitCode === 127)
        return "nocli";
    return "failed";
}

// The half of the panel's STALE line that names what is left to do. "ok" lands
// on the same text as "idle" on purpose: the helper ran clean and the token is
// still stale, so the refresh was not the missing piece and a real `claude` run
// is still the answer.
function refreshHint(refreshState) {
    switch (refreshState) {
    case "running":
        return "REFRESHING";
    case "nocli":
        return "NO CLAUDE CLI";
    case "failed":
        return "RUN CLAUDE AUTH LOGIN";
    default:
        return "RUN CLAUDE TO REFRESH";
    }
}

// ---- Codex (`codex app-server` JSON-RPC) ----

// One line of the app-server's stdout, already framed as newline-delimited
// JSON (no Content-Length headers, verified against
// codex_usage_scanner.py's rpc_request(), which writes/reads exactly one
// JSON object per line). Reply to `account/read`: {id, result: {account}}.
function parseCodexAccount(body) {
    var msg = _parseRpcMessage(body);
    if (!msg.ok)
        return msg;

    var account = _isObject(msg.result) ? msg.result.account : null;
    if (!_isObject(account))
        return { ok: false, error: "missing_fields" };

    var planType = typeof account.planType === "string" ? account.planType
        : (typeof account.type === "string" ? account.type : "");
    return { ok: true, planType: planType };
}

// Reply to `account/rateLimits/read`: {id, result: {rateLimits: {planType,
// primary, secondary}}}, each window `{usedPercent, windowDurationMins,
// resetsAt}` (resetsAt is unix seconds).
function parseCodexRateLimits(body) {
    var msg = _parseRpcMessage(body);
    if (!msg.ok)
        return msg;

    var limits = _isObject(msg.result) ? msg.result.rateLimits : null;
    if (!_isObject(limits))
        return { ok: false, error: "missing_fields" };

    var rows = [];
    var primary = _codexWindowRow(limits.primary);
    if (primary)
        rows.push(primary);
    var secondary = _codexWindowRow(limits.secondary);
    if (secondary)
        rows.push(secondary);
    if (rows.length === 0)
        return { ok: false, error: "missing_fields" };

    return {
        ok: true,
        planType: typeof limits.planType === "string" ? limits.planType : "",
        rows: rows
    };
}

function _parseRpcMessage(body) {
    var msg;
    try {
        msg = JSON.parse(body);
    } catch (e) {
        return { ok: false, error: "malformed_json" };
    }
    if (!_isObject(msg))
        return { ok: false, error: "malformed_json" };
    return { ok: true, result: msg.result };
}

function _codexWindowRow(window) {
    if (!_isObject(window))
        return null;
    var used = Number(window.usedPercent);
    if (!isFinite(used) || used < 0)
        return null;

    var mins = Number(window.windowDurationMins);
    var label = "WINDOW";
    if (isFinite(mins) && mins > 0) {
        if (mins === 10080)
            label = "WEEKLY";
        else if (mins % 60 === 0)
            label = (mins / 60) + "H WINDOW";
        else
            label = mins + "M WINDOW";
    }

    var resetsAt = "";
    var reset = Number(window.resetsAt);
    if (isFinite(reset) && reset > 0)
        resetsAt = new Date(reset * 1000).toISOString();

    return { label: label, percent: Math.min(1, used / 100), resetsAt: resetsAt };
}

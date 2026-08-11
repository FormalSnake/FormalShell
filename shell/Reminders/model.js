.pragma library

// Pure reminder model: duration parsing, entry shape, the due split, and
// every label the bar cell / summary notification / IPC reply render. No
// Quickshell import, no Date.now() inside any function (the clock is always
// a `nowMs` parameter), and nothing mutates its argument. ReminderService.qml
// holds the wiring; this file holds all the logic worth testing.

var MAX_DURATION_SECONDS = 30 * 24 * 60 * 60;

var _UNIT_SECONDS = { h: 3600, m: 60, s: 1 };

// Which unit a bare (unit-less) number takes, keyed by the unit of the token
// before it: the first token defaults to minutes ("10" is ten minutes), and
// a later one drops to the next smaller unit ("1h30" is 90 minutes, "5m30"
// is 5m30s). There is no entry for "s", so a bare number after seconds is a
// parse failure rather than a silent reinterpretation.
var _BARE_UNIT_AFTER = { "": "m", "h": "m", "m": "s" };

var _TOKEN_RE = /(\d+)([hms]?)/g;

function _text(value) {
    return String(value === undefined || value === null ? "" : value);
}

function _pad2(n) {
    return (n < 10 ? "0" : "") + n;
}

// Seconds, or null when the whole string is not a duration. Whitespace is
// illegal here by design: parseSpec has already split the duration off the
// message before this runs, so a space inside the duration token itself is a
// typo, not a separator.
function parseDuration(text) {
    var s = _text(text).trim().toLowerCase();
    if (s === "" || /\s/.test(s))
        return null;

    _TOKEN_RE.lastIndex = 0;
    var cursor = 0;
    var total = 0;
    var prevUnit = "";
    var match;

    while ((match = _TOKEN_RE.exec(s)) !== null) {
        // Every token must butt against the previous one: anything the
        // grammar does not cover (a sign, a stray letter) shows up as a gap.
        if (match.index !== cursor)
            return null;
        cursor = _TOKEN_RE.lastIndex;

        var unit = match[2];
        if (unit === "") {
            unit = _BARE_UNIT_AFTER[prevUnit];
            if (unit === undefined)
                return null;
        }
        total += parseInt(match[1], 10) * _UNIT_SECONDS[unit];
        prevUnit = unit;
    }

    if (cursor !== s.length)
        return null;
    if (total <= 0 || total > MAX_DURATION_SECONDS)
        return null;
    return total;
}

// "25m coffee break" -> { seconds: 1500, message: "coffee break" }. Splits on
// the first run of whitespace: first token is the duration, the rest is the
// message verbatim. This is the shape the menu's single input field and
// `reminder set` both produce.
function parseSpec(text) {
    var s = _text(text).trim();
    if (s === "")
        return null;

    var split = s.search(/\s/);
    var seconds = parseDuration(split < 0 ? s : s.slice(0, split));
    if (seconds === null)
        return null;

    return { seconds: seconds, message: split < 0 ? "" : s.slice(split).trim() };
}

// The id is an opaque string, never parsed downstream. `serial` only
// separates two reminders set within the same millisecond.
function makeEntry(seconds, message, nowMs, serial) {
    return {
        id: "rem-" + nowMs + "-" + serial,
        message: _text(message),
        setAt: nowMs,
        dueAt: nowMs + seconds * 1000
    };
}

function _byDueAt(a, b) {
    return a.dueAt - b.dueAt;
}

// Sorted ascending by dueAt, which is what lets barLabel and due() read the
// soonest entry off the front instead of scanning.
function add(list, entry) {
    return (Array.isArray(list) ? list : []).concat([entry]).sort(_byDueAt);
}

// state.json is a user-editable file the shell only reads, so an arbitrary
// value can arrive here: anything without a usable id and dueAt is dropped
// rather than rendered as a broken row.
function normalize(raw) {
    if (!Array.isArray(raw))
        return [];

    return raw.filter(function (e) {
        return e !== null && typeof e === "object"
            && typeof e.id === "string" && e.id !== ""
            && typeof e.dueAt === "number" && isFinite(e.dueAt);
    }).map(function (e) {
        return {
            id: e.id,
            message: _text(e.message),
            setAt: typeof e.setAt === "number" && isFinite(e.setAt) ? e.setAt : e.dueAt,
            dueAt: e.dueAt
        };
    }).sort(_byDueAt);
}

// `remaining` is the SAME array identity as `list` when nothing fired: the
// service leans on that to skip a state.json write on every one of its 1s
// ticks. An entry whose dueAt passed while the shell was down is treated
// exactly like one that just crossed, so it fires on the first tick after
// state.json loads (see ReminderService.qml's header for why late beats
// silently dropped).
function due(list, nowMs) {
    var fired = [];
    var remaining = [];

    list.forEach(function (e) {
        if (e.dueAt <= nowMs)
            fired.push(e);
        else
            remaining.push(e);
    });

    return { fired: fired, remaining: fired.length === 0 ? list : remaining };
}

// Rounded up so a still-pending reminder never displays 00:00, which would
// read as already fired.
function remainingSeconds(entry, nowMs) {
    return Math.max(0, Math.ceil((entry.dueAt - nowMs) / 1000));
}

// Width is stability-driven (DESIGN.md §2 item 5 names countdown as a
// numeric display that must not jitter): always two-digit minutes below an
// hour, widening exactly once at the hour boundary.
function countdownLabel(seconds) {
    var total = Math.max(0, Math.floor(seconds));
    var hours = Math.floor(total / 3600);
    var minutes = Math.floor((total % 3600) / 60);
    var secs = total % 60;

    if (hours > 0)
        return hours + ":" + _pad2(minutes) + ":" + _pad2(secs);
    return _pad2(minutes) + ":" + _pad2(secs);
}

// The bar cell's text: soonest countdown alone, or fused with the count via
// the spaced slash DESIGN.md §2 item 10 mandates for meta pairs. list[0] is
// the soonest because add() and normalize() both keep the list sorted.
function barLabel(list, nowMs) {
    if (!list || list.length === 0)
        return "";

    var soonest = countdownLabel(remainingSeconds(list[0], nowMs));
    return list.length === 1 ? soonest : soonest + " / " + list.length;
}

function summaryLines(list, nowMs) {
    return (list || []).map(function (e) {
        return e.message + " / " + countdownLabel(remainingSeconds(e, nowMs));
    });
}

// 24h wall clock in the local timezone, for callers that confirm when a
// reminder lands rather than counting down to it.
function dueClock(dueAtMs) {
    var d = new Date(dueAtMs);
    return _pad2(d.getHours()) + ":" + _pad2(d.getMinutes());
}

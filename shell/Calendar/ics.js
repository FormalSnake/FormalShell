.pragma library

// Pure RFC 5545 VEVENT reader for the calendar panel's events feature (M6
// Task 5's outcome — see docs/spikes/2026-07-28-eds-calendar-events.md).
// Feeds from both of CalendarEventsService's backends: local .ics files in
// a khal/vdir-style directory, and the raw ICS the formalshell-eds
// companion CLI prints from EDS/GOA (M12 Task 3).
//
// Recurring VEVENTs (RRULE) expand into concrete instances within a bounded
// query window (parseEvents's optional windowStart/windowEnd; default
// yesterday through 45 days out, matching formalshell-eds's fetch window).
// Supported subset: FREQ=DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, COUNT,
// UNTIL, BYDAY on weekly rules, and EXDATE as simple local-date matches.
// Anything else in the rule — BYSETPOS, BYMONTHDAY, ordinal BYDAY (1MO),
// an unparseable EXDATE, any part not named above — leaves the anchoring
// VEVENT as a single occurrence at its DTSTART: honest under-expansion,
// never a guessed instance. Also out of scope: RECURRENCE-ID overrides
// (the override renders alongside the generated instance), WKST (accepted
// but ignored; weeks are Monday-based relative to DTSTART's week), and
// timezone-aware stepping (instances keep DTSTART's local wall-clock time,
// the same single-timezone stance _parseDateValue documents). Instances
// carry `uid#<localstamp>` uids so mergeEvents dedupes per instance and
// both backends' expansions of the same master collapse together.

// RFC 5545 §3.1: content lines longer than 75 octets are folded onto a
// continuation line starting with exactly one space or tab. Unfold before
// any line-oriented parsing, same rule wl-clipboard's ICS-adjacent formats
// don't need but every real .ics export relies on.
function unfold(text) {
    return text.replace(/\r\n/g, "\n").replace(/\n[ \t]/g, "");
}

function _unescape(value) {
    return value.replace(/\\n/gi, "\n").replace(/\\,/g, ",").replace(/\\;/g, ";").replace(/\\\\/g, "\\");
}

// "DTSTART;VALUE=DATE:20260315" (all-day) / "DTSTART:20260315T090000Z"
// (UTC) / "DTSTART;TZID=Europe/Madrid:20260315T090000" (zoned or floating)
// -> { date, allDay }. TZID offsets are not resolved: a zoned or floating
// time is read as local wall-clock time — reasonable for a single-timezone
// khal setup, a documented limitation otherwise.
function _parseDateValue(params, value) {
    var allDay = /VALUE=DATE\b/.test(params) && !/VALUE=DATE-TIME/.test(params);
    var m = value.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/);
    if (!m)
        return null;
    var y = parseInt(m[1], 10), mo = parseInt(m[2], 10) - 1, d = parseInt(m[3], 10);
    if (!m[4])
        return { date: new Date(y, mo, d), allDay: true };
    var h = parseInt(m[4], 10), mi = parseInt(m[5], 10), s = parseInt(m[6], 10);
    var date = m[7] ? new Date(Date.UTC(y, mo, d, h, mi, s)) : new Date(y, mo, d, h, mi, s);
    return { date: date, allDay: allDay };
}

// One VEVENT block's unfolded body -> { uid, summary, start, end, allDay,
// rrule, exdates, exdateBad }, or null when DTSTART is missing or
// unparseable — an event this reducer can't place on the grid is dropped
// rather than rendered wrong. rrule/exdates/exdateBad are parseEvents-
// internal; its output objects never carry them.
function _parseEvent(block) {
    var lines = block.split("\n");
    var uid = "", summary = "", start = null, end = null, allDay = false;
    var rrule = "", exdates = [], exdateBad = false;
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var colon = line.indexOf(":");
        if (colon < 0)
            continue;
        var left = line.slice(0, colon);
        var value = line.slice(colon + 1);
        var semi = left.indexOf(";");
        var name = (semi < 0 ? left : left.slice(0, semi)).toUpperCase();
        var params = semi < 0 ? "" : left.slice(semi + 1);

        if (name === "UID") {
            uid = value;
        } else if (name === "SUMMARY") {
            summary = _unescape(value);
        } else if (name === "DTSTART") {
            var parsedStart = _parseDateValue(params, value);
            if (parsedStart) {
                start = parsedStart.date;
                allDay = parsedStart.allDay;
            }
        } else if (name === "DTEND") {
            var parsedEnd = _parseDateValue(params, value);
            if (parsedEnd)
                end = parsedEnd.date;
        } else if (name === "RRULE") {
            rrule = value;
        } else if (name === "EXDATE") {
            var exValues = value.split(",");
            for (var j = 0; j < exValues.length; j++) {
                var parsedEx = _parseDateValue(params, exValues[j]);
                if (parsedEx)
                    exdates.push(parsedEx.date);
                else
                    exdateBad = true;
            }
        }
    }
    if (!start)
        return null;
    return { uid: uid, summary: summary || "(untitled)", start: start, end: end, allDay: allDay, rrule: rrule, exdates: exdates, exdateBad: exdateBad };
}

var _DAY_CODES = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };
// Safety bound on expansion loops, not a tuning knob: candidate stepping is
// day-granular at worst, so this covers ~270 years of scanning before an
// event is silently truncated.
var _MAX_ITERATIONS = 100000;

// RRULE value -> { freq, interval, count, until, byday } for the supported
// subset, or null for anything outside it (the caller then keeps the single
// anchor). count 0 means unbounded; until is an inclusive local instant
// (date-only UNTIL reads as the end of that local day); byday is an array
// of getDay() codes, weekly-only, plain two-letter forms only.
function _parseRrule(value) {
    var rule = { freq: "", interval: 1, count: 0, until: null, byday: null };
    var parts = value.split(";");
    for (var i = 0; i < parts.length; i++) {
        var eq = parts[i].indexOf("=");
        if (eq < 0)
            return null;
        var key = parts[i].slice(0, eq).toUpperCase();
        var val = parts[i].slice(eq + 1);
        if (key === "FREQ") {
            rule.freq = val.toUpperCase();
        } else if (key === "INTERVAL") {
            rule.interval = parseInt(val, 10);
            if (!(rule.interval >= 1))
                return null;
        } else if (key === "COUNT") {
            rule.count = parseInt(val, 10);
            if (!(rule.count >= 1))
                return null;
        } else if (key === "UNTIL") {
            var parsed = _parseDateValue("", val);
            if (!parsed)
                return null;
            rule.until = parsed.allDay ? new Date(parsed.date.getFullYear(), parsed.date.getMonth(), parsed.date.getDate(), 23, 59, 59) : parsed.date;
        } else if (key === "BYDAY") {
            var days = val.toUpperCase().split(",");
            rule.byday = [];
            for (var j = 0; j < days.length; j++) {
                if (!(days[j] in _DAY_CODES))
                    return null;
                rule.byday.push(_DAY_CODES[days[j]]);
            }
        } else if (key !== "WKST") {
            return null;
        }
    }
    if (rule.freq !== "DAILY" && rule.freq !== "WEEKLY" && rule.freq !== "MONTHLY" && rule.freq !== "YEARLY")
        return null;
    if (rule.byday && rule.freq !== "WEEKLY")
        return null;
    return rule;
}

// Calendar arithmetic on local wall-clock fields — day steps across a DST
// boundary keep the event's local time, which ms arithmetic would not.
function _shiftDate(base, days, months, years) {
    return new Date(base.getFullYear() + years, base.getMonth() + months, base.getDate() + days, base.getHours(), base.getMinutes(), base.getSeconds());
}

// k-th candidate occurrence for the non-BYDAY frequencies, or null when the
// target month/year has no such calendar date (Jan 31 monthly in February,
// Feb 29 yearly off-leap) — RFC 5545 skips those rather than shifting them,
// and they don't consume COUNT.
function _nthOccurrence(start, freq, n) {
    if (freq === "DAILY")
        return _shiftDate(start, n, 0, 0);
    if (freq === "WEEKLY")
        return _shiftDate(start, 7 * n, 0, 0);
    var d = freq === "MONTHLY" ? _shiftDate(start, 0, n, 0) : _shiftDate(start, 0, 0, n);
    return d.getDate() === start.getDate() && (freq === "MONTHLY" || d.getMonth() === start.getMonth()) ? d : null;
}

function _mondayOf(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() - (d.getDay() + 6) % 7);
}

function _matchesExdate(s, exdates) {
    for (var i = 0; i < exdates.length; i++) {
        if (_sameDate(s, exdates[i]))
            return true;
    }
    return false;
}

// One occurrence through the bounds, in RFC evaluation order: UNTIL and
// COUNT define the recurrence set (so pre-window and EXDATE-removed members
// still consume COUNT), EXDATE and the window then filter what renders.
// "stop" ends the scan (candidates are monotonic), "skip" drops just this
// one, "take" emits it.
function _admit(s, rule, exdates, winStart, winEnd, state) {
    if (rule.until && s.getTime() > rule.until.getTime())
        return "stop";
    state.made++;
    if (rule.count > 0 && state.made > rule.count)
        return "stop";
    if (s.getTime() > winEnd.getTime())
        return "stop";
    if (s.getTime() < winStart.getTime() || _matchesExdate(s, exdates))
        return "skip";
    return "take";
}

function _instance(event, start) {
    var end = event.end ? new Date(start.getTime() + (event.end.getTime() - event.start.getTime())) : null;
    var uid = event.uid === "" ? "" : event.uid + "#" + _stamp(start);
    return { uid: uid, summary: event.summary, start: start, end: end, allDay: event.allDay };
}

function _stamp(d) {
    function p(n) {
        return (n < 10 ? "0" : "") + n;
    }
    return "" + d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + "T" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds());
}

// Recurring event + supported rule -> its in-window instances. DTSTART is
// always the recurrence set's first member (RFC 5545 leaves an
// out-of-sync DTSTART undefined; counting it is the common reading). For
// weekly BYDAY the scan is day-granular with week parity taken against
// DTSTART's Monday-based week.
function _expandRecurring(event, rule, winStart, winEnd) {
    var instances = [];
    var state = { made: 0 };
    var startWeek = rule.byday ? _mondayOf(event.start).getTime() : 0;
    for (var i = 0; i < _MAX_ITERATIONS; i++) {
        var s;
        if (rule.byday) {
            s = _shiftDate(event.start, i, 0, 0);
            var member = i === 0
                || (rule.byday.indexOf(s.getDay()) >= 0
                    && Math.round((_mondayOf(s).getTime() - startWeek) / 604800000) % rule.interval === 0);
            if (!member) {
                if (s.getTime() > winEnd.getTime())
                    break;
                continue;
            }
        } else {
            s = _nthOccurrence(event.start, rule.freq, i * rule.interval);
            if (!s)
                continue;
        }
        var verdict = _admit(s, rule, event.exdates, winStart, winEnd, state);
        if (verdict === "stop")
            break;
        if (verdict === "take")
            instances.push(_instance(event, s));
    }
    return instances;
}

function _single(event) {
    return { uid: event.uid, summary: event.summary, start: event.start, end: event.end, allDay: event.allDay };
}

// Concatenated .ics text (any number of VCALENDARs, each with any number of
// VEVENTs) -> a flat, unsorted array of parsed events, with recurring
// events expanded into instances inside [windowStart, windowEnd] (both
// inclusive instants; default yesterday through 45 days out, see header).
// Non-recurring events pass through regardless of the window. Garbage input
// (no VEVENT blocks at all) yields an empty array rather than throwing.
function parseEvents(text, windowStart, windowEnd) {
    if (!windowStart || !windowEnd) {
        var now = new Date();
        if (!windowStart)
            windowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
        if (!windowEnd)
            windowEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 45, 23, 59, 59);
    }
    var unfolded = unfold(text);
    var events = [];
    var re = /BEGIN:VEVENT\n([\s\S]*?)END:VEVENT/g;
    var m;
    while ((m = re.exec(unfolded)) !== null) {
        var event = _parseEvent(m[1]);
        if (!event)
            continue;
        var rule = event.rrule !== "" && !event.exdateBad ? _parseRrule(event.rrule) : null;
        if (!rule) {
            events.push(_single(event));
            continue;
        }
        var instances = _expandRecurring(event, rule, windowStart, windowEnd);
        for (var i = 0; i < instances.length; i++)
            events.push(instances[i]);
    }
    return events;
}

// Two parsed-event arrays -> one, deduped by UID with `primary` winning a
// collision (the merge CalendarEventsService runs over its ics and EDS
// backends). An event with an empty UID identifies nothing, so those are
// always kept rather than collapsed onto each other.
function mergeEvents(primary, secondary) {
    var seen = Object.create(null);
    var merged = [];
    var all = primary.concat(secondary);
    for (var i = 0; i < all.length; i++) {
        var event = all[i];
        if (event.uid !== "") {
            if (seen[event.uid])
                continue;
            seen[event.uid] = true;
        }
        merged.push(event);
    }
    return merged;
}

function _sameDate(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

// Events whose local start date falls on `date` — the day-cell dot/list
// query the panel makes once per visible day.
function eventsOnDate(events, date) {
    return events.filter(function (e) {
        return _sameDate(e.start, date);
    });
}

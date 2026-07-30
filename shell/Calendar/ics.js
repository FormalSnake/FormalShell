.pragma library

// Pure RFC 5545 VEVENT reader for the calendar panel's events feature (M6
// Task 5's outcome — see docs/spikes/2026-07-28-eds-calendar-events.md).
// Feeds from both of CalendarEventsService's backends: local .ics files in
// a khal/vdir-style directory, and the raw ICS the formalshell-eds
// companion CLI prints from EDS/GOA (M12 Task 3). No RRULE expansion: a
// recurring event's anchoring VEVENT is read as a single occurrence and
// nothing else — a documented v1 limitation, not an oversight.

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

// One VEVENT block's unfolded body -> { uid, summary, start, end, allDay },
// or null when DTSTART is missing or unparseable — an event this reducer
// can't place on the grid is dropped rather than rendered wrong.
function _parseEvent(block) {
    var lines = block.split("\n");
    var uid = "", summary = "", start = null, end = null, allDay = false;
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
        }
    }
    if (!start)
        return null;
    return { uid: uid, summary: summary || "(untitled)", start: start, end: end, allDay: allDay };
}

// Concatenated .ics text (any number of VCALENDARs, each with any number of
// VEVENTs) -> a flat, unsorted array of parsed events. Garbage input (no
// VEVENT blocks at all) yields an empty array rather than throwing.
function parseEvents(text) {
    var unfolded = unfold(text);
    var events = [];
    var re = /BEGIN:VEVENT\n([\s\S]*?)END:VEVENT/g;
    var m;
    while ((m = re.exec(unfolded)) !== null) {
        var event = _parseEvent(m[1]);
        if (event)
            events.push(event);
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

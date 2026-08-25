.pragma library

// Agenda shaping for the calendar panel's day ledger (M6 Task 5's events
// section, extended): what order the selected day's rows appear in, what
// time each one prints in its left column, and where the current moment
// sits among them. Pure functions over the event objects Ics.parseEvents
// produces ({ uid, summary, start, end, allDay }), so CalendarPanel keeps
// only the rendering.

var MS_PER_DAY = 86400000;

// All-day events lead, they have no clock time to sort against and cover
// the whole day the ledger is listing, then the timed ones in
// chronological order. Summary breaks a same-minute tie so two events keep
// a stable order across re-renders instead of following whatever order
// mergeEvents happened to concatenate its two backends in.
function sortForDay(events) {
    return events.slice().sort(function (a, b) {
        if (a.allDay !== b.allDay)
            return a.allDay ? -1 : 1;
        var delta = a.start.getTime() - b.start.getTime();
        if (delta !== 0)
            return delta;
        return a.summary < b.summary ? -1 : a.summary > b.summary ? 1 : 0;
    });
}

function _startOfDay(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
}

// Whole local days between two instants, so a DST-shifted day still counts
// as one, ms division alone would round a 23-hour day down to zero.
function _dayDelta(from, to) {
    return Math.round((_startOfDay(to) - _startOfDay(from)) / MS_PER_DAY);
}

// 24-hour by default, matching the shell's own `hh:mm` convention;
// `twelveHour` writes the AM/PM notation the bar clock's twin presets use
// (ClockModel.usesMeridiem resolves which is live).
function clockTime(date, twelveHour) {
    var h = date.getHours();
    var m = (date.getMinutes() < 10 ? "0" : "") + date.getMinutes();
    if (!twelveHour)
        return (h < 10 ? "0" : "") + h + ":" + m;
    return (h % 12 === 0 ? 12 : h % 12) + ":" + m + (h < 12 ? " AM" : " PM");
}

// A row's left column: "ALL DAY", a bare "09:00" for an event with no
// DTEND, or the "09:00-10:30" range. An end landing on a later local day
// takes a "+2D" tail rather than printing a clock time that reads as this
// day's. RFC 5545 makes DTEND exclusive for a VALUE=DATE event, so an
// all-day span covering n days ends n midnights out and its tail counts
// n-1.
function timeLabel(event, twelveHour) {
    if (event.allDay) {
        var days = event.end ? _dayDelta(event.start, event.end) : 1;
        return days > 1 ? "ALL DAY +" + (days - 1) + "D" : "ALL DAY";
    }
    var start = clockTime(event.start, twelveHour);
    if (!event.end || event.end.getTime() <= event.start.getTime())
        return start;
    var end = clockTime(event.end, twelveHour);
    // A 12-hour range with both ends in the same half of the day prints one
    // meridiem, on the right, where it covers both: "9:00-10:30 AM".
    if (twelveHour && (event.start.getHours() < 12) === (event.end.getHours() < 12))
        start = start.slice(0, start.length - 3);
    var over = _dayDelta(event.start, event.end);
    return start + "-" + end + (over > 0 ? " +" + over + "D" : "");
}

// "past" / "now" / "upcoming" for a timed event against `now`. An all-day
// event is "allday" and never any of the three: it runs for the entire day
// it is listed under, so the running-row treatment would fill every all-day
// row and say nothing.
function status(event, now) {
    if (event.allDay)
        return "allday";
    var t = now.getTime();
    var start = event.start.getTime();
    if (t < start)
        return "upcoming";
    // A zero-length event (no DTEND, or one equal to DTSTART) is past the
    // moment it starts rather than running forever.
    var end = event.end ? event.end.getTime() : start;
    return t < end ? "now" : "past";
}

function hasRunning(events, now) {
    for (var i = 0; i < events.length; i++) {
        if (status(events[i], now) === "now")
            return true;
    }
    return false;
}

// The earliest event of the day still to start, or null once they all have.
function nextUp(events, now) {
    var best = null;
    for (var i = 0; i < events.length; i++) {
        if (status(events[i], now) !== "upcoming")
            continue;
        if (!best || events[i].start.getTime() < best.start.getTime())
            best = events[i];
    }
    return best;
}

// The longest label the day will print. The panel renders this into a
// hidden gauge and sizes every row's time column off it, so the summaries
// line up in one column instead of each starting wherever its own time ran
// out.
function widestLabel(events, twelveHour) {
    var widest = "";
    for (var i = 0; i < events.length; i++) {
        var label = timeLabel(events[i], twelveHour);
        if (label.length > widest.length)
            widest = label;
    }
    return widest;
}

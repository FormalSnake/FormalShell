.pragma library
.import "../Clock/model.js" as ClockModel

// The calendar panel's month grid, as pure functions: which 42 days a month
// shows, which ISO week each row belongs to, and how an index into that flat
// list relates to a date. CalendarPanel keeps only the rendering and the
// keyboard cursor, which addresses this same flat index (Panel's
// `cursorColumns`), so the maths is testable without any Quickshell type,
// the same split agenda.js and progress.js already use.

var COLUMNS = 7;
var ROWS = 6;
var CELLS = COLUMNS * ROWS;

// Monday-first, always 42 cells regardless of month length, so stepping
// months never resizes the card: a 28-day February and a 31-day month both
// pad out with days from the adjacent months. Each cell carries its fully
// resolved year/month, so selecting a padding day names a real adjacent-month
// date rather than a day number with no month behind it.
function monthCells(year, month) {
    var firstWeekday = (new Date(year, month, 1).getDay() + 6) % 7;
    var start = new Date(year, month, 1 - firstWeekday);
    var cells = [];
    for (var i = 0; i < CELLS; i++) {
        var d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
        cells.push({
            year: d.getFullYear(),
            month: d.getMonth(),
            day: d.getDate(),
            inMonth: d.getMonth() === month && d.getFullYear() === year
        });
    }
    return cells;
}

// One ISO week number per grid row, read off that row's Thursday (index 3 of
// its 7 Monday-first cells): the definition of the week a row belongs to
// whenever its days span a month or year boundary.
function weekNumbers(cells) {
    var weeks = [];
    for (var r = 0; r < ROWS; r++) {
        var thursday = cells[r * COLUMNS + 3];
        weeks.push(ClockModel.isoWeek(thursday.year, thursday.month, thursday.day));
    }
    return weeks;
}

function dateAt(cells, index) {
    if (index < 0 || index >= cells.length)
        return null;
    var cell = cells[index];
    return new Date(cell.year, cell.month, cell.day);
}

function sameDate(a, b) {
    return a.getFullYear() === b.getFullYear()
        && a.getMonth() === b.getMonth()
        && a.getDate() === b.getDate();
}

// Where the cursor lands when the panel opens or the month steps: the given
// date's own cell when the grid is showing it, else the first day of the
// month on screen. Never -1, so the reveal-only first keypress always has a
// real position to show.
function indexOfDate(cells, date) {
    for (var i = 0; i < cells.length; i++) {
        var cell = cells[i];
        if (cell.year === date.getFullYear() && cell.month === date.getMonth() && cell.day === date.getDate())
            return i;
    }
    for (var j = 0; j < cells.length; j++) {
        if (cells[j].inMonth)
            return j;
    }
    return 0;
}

// The events dot under a day number. Only in-month days carry one: the
// padding days either side belong to the adjacent months and are dimmed
// rather than dotted.
function showsEventDot(cell, eventCount) {
    return !!cell && cell.inMonth && eventCount > 0;
}

// Month stepping, kept here so wrapping December into January carries the
// year with it in one tested place.
function stepMonth(year, month, delta) {
    var m = month + delta;
    return { year: year + Math.floor(m / 12), month: ((m % 12) + 12) % 12 };
}

function isoDate(d) {
    var m = d.getMonth() + 1;
    var day = d.getDate();
    return d.getFullYear() + "-" + (m < 10 ? "0" + m : m) + "-" + (day < 10 ? "0" + day : day);
}

// The IPC entry's own parse (CalendarIpc's `select` verb): strict YYYY-MM-DD,
// with a component round-trip so 2026-02-31 is rejected rather than silently
// becoming March 3rd. Returns a Date or null.
function parseIsoDate(iso) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
    if (!m)
        return null;
    var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
    if (d.getFullYear() !== Number(m[1]) || d.getMonth() !== Number(m[2]) - 1 || d.getDate() !== Number(m[3]))
        return null;
    return d;
}

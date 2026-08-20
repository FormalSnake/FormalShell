.pragma library

// Pure date-format math for the bar clock and the calendar panel (no
// Qt/QML dependency, unit tested under qmltestrunner). QML owns the actual
// rendering: Qt.formatDateTime(date, format) turns a ring entry into text,
// and Qt.locale() supplies localized weekday/month names where the panel
// wants them.

var MS_PER_DAY = 86400000;

// Right-click on the bar clock walks this ring in order. Each 24-hour
// preset sits next to its 12-hour twin so one more click swaps notation
// without walking the whole ring; the ISO-week preset has no twin of its
// own since ISO 8601 always writes time on a 24-hour clock.
var CLOCK_FORMATS = [
    "hh:mm",
    "h:mm AP",
    "ddd hh:mm",
    "ddd d MMM hh:mm",
    "yyyy-MM-dd hh:mm",
    "d MMM 'W'ww"
];

function formats() {
    return CLOCK_FORMATS.slice();
}

function pad2(value) {
    var n = Number(value);
    return (n < 10 ? "0" : "") + n;
}

// ISO-8601 week number: the week owning the Thursday of `date`'s
// Monday-based week. `month` is 0-indexed, matching JS Date.
function isoWeek(year, month, day) {
    var date = new Date(Date.UTC(year, month, day));
    var isoWeekday = date.getUTCDay() || 7; // Sunday (0) becomes 7
    date.setUTCDate(date.getUTCDate() + 4 - isoWeekday);
    var yearStart = Date.UTC(date.getUTCFullYear(), 0, 1);
    return Math.ceil(((date.getTime() - yearStart) / MS_PER_DAY + 1) / 7);
}

// Every "ww" in `format` becomes the zero-padded ISO week for `date`,
// ahead of Qt.formatDateTime: Qt has no ISO-week specifier, and none of
// its recognized tokens are digits, so a plain string substitution is safe
// to run first.
function substituteIsoWeek(format, date) {
    var week = pad2(isoWeek(date.getFullYear(), date.getMonth(), date.getDate()));
    return format.replace(/ww/g, week);
}

// Which notation a ring entry writes. Every 12-hour preset above is its
// 24-hour neighbour's twin with Qt's AP specifier added, so the calendar
// panel's agenda reads the live format here rather than carrying a second
// notation setting of its own. Qt's single-letter A/a forms are not in the
// ring and are not recognized.
function usesMeridiem(format) {
    return /AP|ap/.test(format);
}

// The entry after `current`. A format that isn't in the ring (hand-edited
// state.json, an old preset dropped from a later release) starts the walk
// at the top rather than throwing.
function nextFormat(current) {
    var index = CLOCK_FORMATS.indexOf(current);
    return CLOCK_FORMATS[(index + 1) % CLOCK_FORMATS.length];
}

if (typeof module !== "undefined") {
    module.exports = {
        CLOCK_FORMATS: CLOCK_FORMATS,
        formats: formats,
        pad2: pad2,
        isoWeek: isoWeek,
        substituteIsoWeek: substituteIsoWeek,
        usesMeridiem: usesMeridiem,
        nextFormat: nextFormat
    };
}

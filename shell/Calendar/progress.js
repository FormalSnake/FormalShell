.pragma library

// Pure calendar-progress math: year-elapsed fraction and (once the M6 Task 4
// easter egg sets birthYear/lifeExpectancy) life-lived fraction. Every
// function takes `now` as an explicit Date argument — no Date.now() inside —
// so CalendarPanel.qml stays a thin binding layer and this stays
// deterministic under test.

function _isLeapYear(year) {
    return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
}

// 0..1 fraction of the current calendar year elapsed. Uses UTC year
// boundaries so a leap year's Feb 29 correctly widens the denominator to
// 366 days without any day-counting of our own — the two Date.UTC calls
// already know how long the year is.
function yearFraction(now) {
    var year = now.getFullYear();
    var start = Date.UTC(year, 0, 1);
    var end = Date.UTC(year + 1, 0, 1);
    return Math.max(0, Math.min(1, (now.getTime() - start) / (end - start)));
}

// 0..1 fraction of an assumed lifespan lived, or null when birthYear/
// lifeExpectancy are missing or out of a sane human range — the easter egg
// must never render a wrong bar off garbage input.
function lifeFraction(now, birthYear, lifeExpectancy) {
    if (!Number.isFinite(birthYear) || !Number.isFinite(lifeExpectancy))
        return null;
    if (birthYear < 1900 || birthYear > now.getFullYear())
        return null;
    if (lifeExpectancy <= 0 || lifeExpectancy > 130)
        return null;

    var start = Date.UTC(birthYear, 0, 1);
    var end = Date.UTC(birthYear + lifeExpectancy, 0, 1);
    return Math.max(0, Math.min(1, (now.getTime() - start) / (end - start)));
}

function formatPercent(fraction) {
    return Math.round(fraction * 100) + "%";
}

// Settings (`calendar.birthYear`/`calendar.lifeExpectancy`) declaratively
// override the runtime state value when present; state.json's own value
// (written by the life-progress easter egg) is the fallback when settings
// is silent — never the other way around, matching Config's read-only-
// settings-wins convention elsewhere in the shell.
function resolveOverride(settingsValue, stateValue) {
    return (settingsValue === undefined || settingsValue === null) ? stateValue : settingsValue;
}

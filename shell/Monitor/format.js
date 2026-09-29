.pragma library

// Display strings for the monitor view. Null, undefined and NaN in, a dash
// out, everywhere: a reading nobody has taken yet must not render as a zero.
// Fractions are 0..1, the repo-wide convention.

function _missing(value) {
    return value === null || value === undefined || !isFinite(value);
}

// Whole percent, for machine-wide figures.
function pct(fraction) {
    if (_missing(fraction))
        return "--";
    return Math.round(fraction * 100) + "%";
}

// One decimal, for a process's share of the whole machine, where 0.4% and
// 4.0% are the difference between idle and busy on a many-thread box.
function procPct(fraction) {
    if (_missing(fraction))
        return "--";
    return (fraction * 100).toFixed(1) + "%";
}

function bytes(value) {
    if (_missing(value))
        return "--";
    var units = ["B", "K", "M", "G", "T"];
    var scaled = value;
    var i = 0;
    while (scaled >= 1024 && i < units.length - 1) {
        scaled /= 1024;
        i++;
    }
    return (i === 0 ? Math.round(scaled) : scaled.toFixed(1)) + units[i];
}

function rate(bytesPerSec) {
    if (_missing(bytesPerSec))
        return "--";
    return bytes(bytesPerSec) + "/s";
}

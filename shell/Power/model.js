.pragma library

// Pure battery threshold + formatting helpers (M16 Task 5). No QML/Qt
// dependency: PowerPanel.qml feeds live UPower readings through
// warnEvent(), persists the returned `fired` for the next call, and
// formats the static BATTERY meta rows with the helpers below.

var DEFAULT_WARN_PCT = 10;
var DEFAULT_CRITICAL_PCT = 5;

function initialFired() {
    return { warn: false, critical: false };
}

// prevPct/pct: whole-number percentages (0..100) — UPower's own 0..1
// fraction is converted exactly once, at the call site, never in here.
// charging: the live discharging/charging state, already resolved to a
// boolean. fired: whatever this function returned last call
// (initialFired() on the very first one). warnPct/criticalPct default to
// settings.json's own defaults (10/5) when omitted.
//
// Charging re-arms both thresholds immediately, regardless of percentage
// — a plugged-in battery is never "discharging" mid-crossing, so a later
// unplug while still low fires again (the "charge interruptions" case).
// While discharging, a threshold fires once when the reading is at/below
// it and hasn't already fired since the last re-arm; a boot (or resume)
// that starts already below a threshold fires immediately — prevPct is
// null on the very first call, so there is nothing to compare against,
// and staying silent about a real critical/low state would be dishonest.
// `notRising` guards the fire against a single noisy uptick (UPower's
// rate estimate can blip for one reading while genuinely still
// discharging) without weakening the re-arm rule: once fired, a
// threshold only clears via charging, never by drifting back above the
// line on its own.
function warnEvent(prevPct, pct, charging, fired, warnPct, criticalPct) {
    warnPct = warnPct === undefined ? DEFAULT_WARN_PCT : warnPct;
    criticalPct = criticalPct === undefined ? DEFAULT_CRITICAL_PCT : criticalPct;
    var prevFired = fired || initialFired();

    if (charging)
        return { fired: initialFired(), event: null };

    var notRising = (prevPct === null || prevPct === undefined) || pct <= prevPct;

    if (notRising && pct <= criticalPct && !prevFired.critical)
        return { fired: { warn: true, critical: true }, event: "critical" };

    if (notRising && pct <= warnPct && !prevFired.warn)
        return { fired: { warn: true, critical: prevFired.critical }, event: "warn" };

    return { fired: prevFired, event: null };
}

// "2H 14M" / "14M" / "1D 3H" — mirrors Usage/usage.js's formatReset shape.
function formatDuration(totalSeconds) {
    var totalMins = Math.floor(totalSeconds / 60);
    var hours = Math.floor(totalMins / 60);
    var mins = totalMins % 60;
    if (hours >= 24)
        return Math.floor(hours / 24) + "D " + (hours % 24) + "H";
    if (hours > 0)
        return hours + "H " + mins + "M";
    return mins + "M";
}

// UPowerDevice.changeRate is signed (positive charging, negative
// discharging, per the pinned quickshell source) — callers already know
// the sign from `state`, so the display text only ever wants the
// magnitude.
function formatRate(watts) {
    return Math.abs(watts).toFixed(1) + "W";
}

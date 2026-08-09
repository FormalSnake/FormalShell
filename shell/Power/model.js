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

// RAPL package power (M20 Task 5c, owner ask: "the W usage right next to
// the W it's charging with"). `energy_uj` accumulates until it reaches
// `max_energy_range_uj`, then the powercap driver resets it to 0 rather
// than overflowing, so a sample pair spanning exactly one wrap needs the
// full range added back onto the naive difference — the same one-wrap
// assumption the kernel's own powercap consumers make (RAPL packages wrap
// on the order of minutes on real hardware, far longer than a poll
// interval measured in seconds).
function raplDeltaUj(prevUj, currUj, maxRangeUj) {
    if (currUj >= prevUj)
        return currUj - prevUj;
    return (maxRangeUj - prevUj) + currUj;
}

// null on a non-positive interval or a still-negative delta (a reset
// outside the wraparound case, e.g. suspend/resume clearing the
// counter) — never a negative or invented wattage.
function raplWatts(prevUj, currUj, maxRangeUj, deltaMs) {
    if (!(deltaMs > 0))
        return null;
    var deltaUj = raplDeltaUj(prevUj, currUj, maxRangeUj);
    if (!(deltaUj >= 0))
        return null;
    return (deltaUj / 1e6) / (deltaMs / 1000);
}

// Two-line `cat energy_uj max_energy_range_uj` stdout -> {energyUj,
// maxRangeUj}. Honest null on anything short of two parseable numbers:
// a root-only energy_uj (PLATYPUS mitigation, user-readable only via a
// udev rule outside this repo) or an absent powercap path both leave
// `cat`'s stdout short a line, same shape as SpeedTest.parseStatBytes.
function parseRaplUj(text) {
    var lines = (text || "").split("\n").map(function (l) { return l.trim(); }).filter(function (l) { return l !== ""; });
    if (lines.length < 2)
        return null;
    var energyUj = parseInt(lines[0], 10);
    var maxRangeUj = parseInt(lines[1], 10);
    if (!isFinite(energyUj) || !isFinite(maxRangeUj) || energyUj < 0 || maxRangeUj <= 0)
        return null;
    return { energyUj: energyUj, maxRangeUj: maxRangeUj };
}

// The battery section's one slash-fused wattage row (DESIGN §2 item 10:
// meta pairs fuse with " / ", never a colon). `cpuPackageW` is null
// whenever RAPL is unreadable or hasn't produced a second sample yet —
// the " / CPU" half is simply absent then, never "/ CPU 0.0W" or a
// stale figure from before the panel reopened.
function formatWattageRow(charging, changeRateW, cpuPackageW) {
    var head = (charging ? "CHARGING " : "DRAW ") + formatRate(changeRateW);
    if (cpuPackageW === null || cpuPackageW === undefined)
        return head;
    return head + " / CPU " + formatRate(cpuPackageW);
}

// Whether the static TIME TO FULL/EMPTY meta rows should render (M-polish
// batch item D, owner-reported: they duplicated the same fields the status
// line above already rotates through). The static rows defer only while
// the rotation is actually going to show those fields — `rotating` already
// requires charging/discharging AND more than one real phrase — so a field
// that would never get a turn in rotation (motion enabled but the device
// isn't charging/discharging) still falls back to rendering statically
// instead of vanishing outright. With motion disabled, `rotating` is
// irrelevant: the status line never advances past phrase 0, so the static
// rows always carry the extra fields. The wattage row (formatWattageRow)
// is NOT part of this dedup group — it replaced the rotation's own RATE
// phrase outright (see PowerPanel.qml's `_phrases`), so it renders
// unconditionally whenever there's a real rate, independent of `rotating`.
function staticFieldsVisible(motionEnabled, rotating) {
    return !(motionEnabled && rotating);
}

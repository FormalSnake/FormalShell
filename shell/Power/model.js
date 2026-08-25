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

// The wattage stat, split so the words land in the label and the figures
// in the mono value (DESIGN.md §1 "Type"). "HOLDING" is the charge
// threshold's own word: the rate is real but near zero there, and calling
// it a draw would misread it.
function rateRowLabel(charging, thresholdActive) {
    if (thresholdActive)
        return "HOLDING";
    return charging ? "CHARGING" : "DRAW";
}

// `cpuPackageW` is null whenever RAPL is unreadable or hasn't produced a
// second sample yet, and the " / CPU" half is simply absent then, never
// "/ CPU 0.0W" or a stale figure from before the panel reopened.
function rateRowValue(changeRateW, cpuPackageW) {
    var head = formatRate(changeRateW);
    if (cpuPackageW === null || cpuPackageW === undefined)
        return head;
    return head + " / CPU " + formatRate(cpuPackageW);
}

// Charge-threshold detection (M26 Task 3, ported from omarchy quattro's
// power/Model.js:52-64, read-reference only). A laptop holding at a
// configured charge limit reports one of three UPower shapes that all mean
// "plugged in but not actually charging toward 100": PendingCharge
// outright, FullyCharged below 99% (the limit sits under what UPower calls
// full), or Charging with a near-zero rate or a time-to-full of 8 hours or
// more (a real charge crawling toward a limit reads the same as a charger
// that can't keep up). `onBattery` is UPower's own aggregate property, not
// a per-device state parse, matching the gate upstream uses. `pct` is a
// whole-number percentage (0..100), same convention as warnEvent above.
// `states` carries the three UPowerDeviceState values the check needs
// (PendingCharge, FullyCharged, Charging) — passed in rather than imported,
// since this file has no Qt/Quickshell dependency.
function chargeThresholdActive(pct, state, changeRate, timeToFull, onBattery, states) {
    if (onBattery)
        return false;
    if (state === states.PendingCharge)
        return true;
    if (state === states.FullyCharged)
        return pct < 99;
    if (state !== states.Charging || pct >= 99)
        return false;
    return Math.abs(changeRate || 0) <= 0.2 || (timeToFull || 0) >= 8 * 60 * 60;
}

// The bar tooltip and the hero meta line's four-way state word.
function chargeStateLabel(pct, state, onBattery, thresholdActive, states) {
    if (thresholdActive)
        return "THRESHOLD";
    if (onBattery)
        return "ON BATTERY";
    if (state === states.FullyCharged || pct >= 100)
        return "FULLY CHARGED";
    return "CHARGING";
}

// Icon name for the battery's state (spec "Icons"): a named set draws
// state, not a decile ramp, so the level detail the old Nerd Font ramp
// carried lives in the percentage beside it. `warnPct` defaults to the
// same 10% warnEvent() uses, so the alert icon and the low-battery
// notification agree on where low starts.
function batteryIcon(pct, onBattery, thresholdActive, warnPct) {
    warnPct = warnPct === undefined ? DEFAULT_WARN_PCT : warnPct;
    if (!onBattery && !thresholdActive)
        return "battery-charging";
    if (pct <= warnPct)
        return "battery-warning";
    if (pct >= 66)
        return "battery-full";
    if (pct >= 33)
        return "battery-medium";
    return "battery-low";
}

// "56.0 WH", or an honest em dash when the device hasn't reported a
// capacity (energyCapacity reads 0 rather than being absent).
function formatWh(wh) {
    return (wh > 0) ? wh.toFixed(1) + " WH" : "—";
}

// UPower's Capacity property is already "design capacity as a percentage"
// (device.hpp: healthPercentage, "health of the device as a percentage of
// its original health") — healthSupported is false when the driver never
// reported one, the honest case to show an em dash rather than a bogus 0%.
function formatHealthPercent(pct, supported) {
    return supported ? Math.round(pct) + "%" : "—";
}

function timeRowLabel(charging) {
    return charging ? "TIME FULL" : "TIME LEFT";
}

// timeToFull/timeToEmpty are 0 whenever the other one applies (the pinned
// quickshell source's own contract, see rateRowValue above) and can
// both briefly read 0 right after a state flip before UPower's next
// estimate lands — an honest em dash rather than "0M" either way.
function timeRowValue(charging, timeToFull, timeToEmpty) {
    var seconds = charging ? timeToFull : timeToEmpty;
    return (seconds > 0) ? formatDuration(seconds) : "—";
}

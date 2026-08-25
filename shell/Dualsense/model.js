.pragma library

// Pure model for the DualSense panel (M29 Task 4). No Quickshell dependency,
// so it's testable head-on against fixture strings shaped exactly like
// hid-playstation's sysfs attributes (plan's research block,
// docs/superpowers/plans/2026-08-18-m29-device-panels.md). Every function
// takes the raw text a `cat` on the matching sysfs file would produce, or
// an absent/unparsable one, and returns a complete default shape rather
// than leaving a caller to guard against null, same discipline as
// Airpods/model.js.
//
// There is no daemon here: DualsenseService reads sysfs directly (a
// power_supply node keyed by Bluetooth MAC, a `leds` node keyed by input
// index, both first-match-wins globs, see that file), and the shell never
// writes any of it. The owner's host units own the lightbar/player-LED
// writes; this model only ever describes what was read.

// warn/critical thresholds mirror the retired `dualsense-bar` command
// module this panel replaces (M29 plan): a straight read of the capacity
// percentage, no charge-direction gating, the sysfs `status` string is
// surfaced separately as `statusLabel` for the hero meta line instead.
var WARN_PERCENT = 20;
var CRITICAL_PERCENT = 10;

function _defaultSupply() {
    return { percent: -1, statusLabel: "", warn: false, critical: false };
}

// capacityText: the `capacity` sysfs file's own text (0-100, in 10% buckets
// on real hardware, but this parses whatever integer it holds rather than
// assuming the bucket size). statusText: the `status` sysfs file's own text
// (POWER_SUPPLY_STATUS values, "Charging", "Discharging", "Full", "Not
// charging", "Unknown"). Either missing/unparsable leaves `percent` at -1,
// which is the panel's "no controller" cue.
function parseSupply(capacityText, statusText) {
    var result = _defaultSupply();
    if (typeof capacityText === "string") {
        var trimmed = capacityText.trim();
        if (/^[0-9]+$/.test(trimmed)) {
            var n = parseInt(trimmed, 10);
            if (n >= 0 && n <= 100)
                result.percent = n;
        }
    }
    result.statusLabel = typeof statusText === "string" ? statusText.trim() : "";
    result.critical = result.percent >= 0 && result.percent <= CRITICAL_PERCENT;
    result.warn = result.percent >= 0 && !result.critical && result.percent <= WARN_PERCENT;
    return result;
}

// text: the `multi_intensity` sysfs file's own text, "R G B" (each 0-255).
// Returns a "#rrggbb" string, or null when the file is absent/malformed,
// the LIGHTBAR row's own presence gate.
function parseLightbar(text) {
    if (typeof text !== "string")
        return null;
    var parts = text.trim().split(/\s+/);
    if (parts.length !== 3)
        return null;
    var channels = [];
    for (var i = 0; i < 3; i++) {
        if (!/^[0-9]+$/.test(parts[i]))
            return null;
        var v = parseInt(parts[i], 10);
        if (v < 0 || v > 255)
            return null;
        channels.push(v);
    }
    function hex2(n) {
        var s = n.toString(16);
        return s.length < 2 ? "0" + s : s;
    }
    return "#" + hex2(channels[0]) + hex2(channels[1]) + hex2(channels[2]);
}

// brightnesses: exactly 5 entries, each the matching `player-N/brightness`
// sysfs file's own text ("0"/"1") or null where that file didn't exist.
// Returns the lit count (0-5), the caller decides "unreadable" (as
// opposed to "readable, none lit") by whether it attempted this call at
// all, since a real DualSense always exposes all five once its lightbar
// node is found.
function parsePlayerLeds(brightnesses) {
    if (!Array.isArray(brightnesses))
        return 0;
    var count = 0;
    for (var i = 0; i < brightnesses.length; i++) {
        if (String(brightnesses[i]).trim() === "1")
            count++;
    }
    return count;
}

// The hero meta line: the sysfs status word alone, e.g. "CHARGING" /
// "DISCHARGING" / "FULL" / "NOT CHARGING", sysfs carries no time-to-empty
// for this device, so nothing is estimated or invented here.
function stateLine(supply) {
    if (!supply || supply.percent < 0 || supply.statusLabel === "")
        return "";
    return supply.statusLabel;
}

.pragma library
.import "../Monitor/gpu.js" as Gpu

// Pure output/display model for DisplayPanel (M17): both compositors' wire
// shapes normalized onto one row contract, plus every derivation the panel
// renders — sort order, the mode/scale/status labels, what a mirror would
// actually do, and whether an output may be switched off at all. No
// Quickshell, no Process, no socket access here, so all of it is testable
// head-on (tests/tst_outputs.qml) — same split as Network/speedtest.js and
// Usage/usage.js.
//
// Row contract, produced by both normalizers and consumed by everything else:
//
//   { name, make, model, x, y, width, height, refresh, scale, enabled, mirrorOf }
//
// `name` is the compositor's own output name and stays an opaque string end
// to end: nothing here parses or compares it numerically, and neither backend
// converts it either (niri keys its Outputs map by name, Hyprland's `monitor`
// keyword takes the name verbatim) — unlike the Number(id) window/workspace
// conversion each backend does at its own wire edge.
//
// `width`/`height`/`refresh` describe the CURRENT mode in physical pixels and
// Hz. A disabled output reports zeros for all three: neither compositor has a
// mode to report for one, and inventing its last known mode would be exactly
// the stubbed value the honest-state rule forbids. `mirrorOf` is "" when the
// output isn't mirroring anything.

// The scale slider's range and quantization. 0.25 is binary-exact, so
// quantizeScale never accumulates float drift across repeated steps.
var SCALE_MIN = 1;
var SCALE_MAX = 3;
var SCALE_STEP = 0.25;

function _text(value) {
    return typeof value === "string" ? value : "";
}

function _int(value) {
    var n = Number(value);
    return isFinite(n) ? Math.round(n) : 0;
}

function _positive(value, fallback) {
    var n = Number(value);
    return (isFinite(n) && n > 0) ? n : fallback;
}

// Fixed-decimal, then back through Number so a whole scale prints "1" rather
// than "1.00" and a two-place refresh prints "60" rather than "60.00".
function _trimNumber(value, decimals) {
    return String(Number(Number(value).toFixed(decimals)));
}

function _gcd(a, b) {
    while (b) {
        var t = a % b;
        a = b;
        b = t;
    }
    return a;
}

// ---- Scale -------------------------------------------------------------

function clampScale(scale) {
    var n = Number(scale);
    if (!isFinite(n))
        return SCALE_MIN;
    return Math.max(SCALE_MIN, Math.min(SCALE_MAX, n));
}

function quantizeScale(scale) {
    return Math.round(clampScale(scale) / SCALE_STEP) * SCALE_STEP;
}

function fractionForScale(scale) {
    return (clampScale(scale) - SCALE_MIN) / (SCALE_MAX - SCALE_MIN);
}

function scaleForFraction(fraction) {
    var f = Number(fraction);
    if (!isFinite(f))
        f = 0;
    f = Math.max(0, Math.min(1, f));
    return quantizeScale(SCALE_MIN + f * (SCALE_MAX - SCALE_MIN));
}

// One notch either way from wherever the compositor currently reports the
// output, quantized first so an off-grid live scale (a compositor is free to
// answer 1.6) still steps onto the grid rather than staying off it forever.
function stepScale(scale, direction) {
    return quantizeScale(quantizeScale(scale) + (direction > 0 ? SCALE_STEP : -SCALE_STEP));
}

function formatScale(scale) {
    var n = Number(scale);
    if (!isFinite(n) || n <= 0)
        return "";
    return _trimNumber(n, 2) + "X";
}

// Hyprland only accepts a scale whose mode divides into whole logical pixels,
// counted in 1/120ths — so the acceptable scales are exactly the divisors of
// gcd(width*120, height*120), and a requested scale rounds UP to the nearest
// one. Read off omarchy's own clean_scale()
// (bin/omarchy-hyprland-monitor-scaling there) and reimplemented. niri has no
// such constraint, so only hyprlandMonitorArg() below applies it.
function cleanScale(scale, width, height) {
    var requested = clampScale(scale);
    var w = _int(width);
    var h = _int(height);
    if (w <= 0 || h <= 0)
        return requested;

    var g = _gcd(w * 120, h * 120);
    var k = Math.round(requested * 120);
    if (k > g)
        k = g;
    if (k < 1)
        k = 1;
    while (g % k !== 0)
        k++;
    return k / 120;
}

// ---- Row derivations ---------------------------------------------------

// Enabled outputs first (the ones an action can act on), then left-to-right /
// top-to-bottom by logical position, then by name — so the order never
// depends on the map key order or array order the compositor answered in.
function sortOutputs(rows) {
    return (rows || []).slice().sort(function (a, b) {
        if (a.enabled !== b.enabled)
            return a.enabled ? -1 : 1;
        if (a.x !== b.x)
            return a.x - b.x;
        if (a.y !== b.y)
            return a.y - b.y;
        return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
    });
}

function findOutput(rows, name) {
    var list = rows || [];
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].name === name)
            return list[i];
    }
    return null;
}

function enabledCount(rows) {
    return (rows || []).filter(function (row) { return row && row.enabled; }).length;
}

// A display may always be switched on; switching one off is refused when it
// is the last enabled output — both compositors would happily leave the
// session with nothing on screen and no surface left to undo it from.
function canToggle(rows, name) {
    var row = findOutput(rows, name);
    if (!row)
        return false;
    if (!row.enabled)
        return true;
    return enabledCount(rows) > 1;
}

// "2560x1440@59.95", or "" for an output with no current mode to report.
function modeLabel(row) {
    if (!row || !row.enabled || row.width <= 0 || row.height <= 0)
        return "";
    var label = row.width + "x" + row.height;
    if (row.refresh > 0)
        label += "@" + _trimNumber(row.refresh, 2);
    return label;
}

// "DELL U2720Q" for the row's second meta line, "" when the compositor
// reports neither half — never a placeholder standing in for hardware
// identity we were not given.
function describe(row) {
    if (!row)
        return "";
    return [_text(row.make), _text(row.model)].filter(function (part) {
        return part !== "";
    }).join(" ");
}

// What turning MIRROR on would do: every other enabled output mirrors
// `primaryName` (the focused output when it is enabled, else the first
// sorted enabled one). `ok:false` with `reason:"single"` when fewer than two
// outputs are enabled — there is nothing to mirror onto, and the panel says
// so rather than rendering a toggle that cannot act.
function mirrorPlan(rows, primaryName) {
    var enabled = sortOutputs(rows).filter(function (row) { return row.enabled; });
    if (enabled.length < 2)
        return { ok: false, reason: "single", primary: "", targets: [] };

    var primary = findOutput(enabled, primaryName) || enabled[0];
    return {
        ok: true,
        reason: "",
        primary: primary.name,
        targets: enabled.filter(function (row) {
            return row.name !== primary.name;
        }).map(function (row) { return row.name; })
    };
}

// Every output currently mirroring something — the set MIRROR OFF has to
// clear, and the reason the toggle reads as on.
function mirroredNames(rows) {
    return (rows || []).filter(function (row) {
        return row && row.mirrorOf !== "";
    }).map(function (row) { return row.name; });
}

// The output every active mirror points at, or "" when nothing mirrors. The
// panel drives one source at a time, so the first mirroring row answers for
// the whole set.
function mirrorSource(rows) {
    var names = mirroredNames(rows);
    if (names.length === 0)
        return "";
    var row = findOutput(rows, names[0]);
    return row ? row.mirrorOf : "";
}

// ---- Backend normalizers -----------------------------------------------

// niri's Response::Outputs payload, already unwrapped from its Reply envelope:
// a map keyed by output name, each value a niri-ipc `Output`
// (niri-ipc/src/lib.rs:1204). `logical` is null exactly when the output is
// disabled ("None if the output is not mapped to any logical output"), which
// is the enabled flag; `current_mode` indexes `modes` and is null for the
// same reason. Refresh rates arrive in millihertz.
function normalizeNiriOutputs(byName) {
    if (!byName || typeof byName !== "object")
        return [];

    var rows = [];
    for (var key in byName) {
        var output = byName[key];
        if (!output || typeof output !== "object")
            continue;

        var logical = output.logical;
        var isEnabled = logical !== null && logical !== undefined;
        var modes = Array.isArray(output.modes) ? output.modes : [];
        var mode = typeof output.current_mode === "number" ? modes[output.current_mode] : null;

        rows.push({
            name: _text(output.name) !== "" ? _text(output.name) : String(key),
            make: _text(output.make),
            model: _text(output.model),
            x: isEnabled ? _int(logical.x) : 0,
            y: isEnabled ? _int(logical.y) : 0,
            width: mode ? _int(mode.width) : 0,
            height: mode ? _int(mode.height) : 0,
            refresh: mode ? _int(mode.refresh_rate) / 1000 : 0,
            scale: isEnabled ? _positive(logical.scale, 1) : 1,
            enabled: isEnabled,
            // niri-ipc's OutputAction has no mirror variant at all, so no niri
            // output is ever mirroring — see NiriBackend's mirrorSupported.
            mirrorOf: ""
        });
    }
    return sortOutputs(rows);
}

// `hyprctl monitors all -j`'s raw stdout — the only Hyprland enumeration that
// includes disabled monitors (plain `monitors` omits them entirely, which is
// also why Quickshell's own Hyprland.monitors model, populated from
// `j/monitors`, cannot back this panel: an output switched off would vanish
// from the very list the user needs to switch it back on from). `mirrorOf` is
// the literal string "none" when the monitor is not mirroring.
function parseHyprlandOutputs(text) {
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return [];
    }
    if (!Array.isArray(data))
        return [];

    var rows = [];
    for (var i = 0; i < data.length; i++) {
        var monitor = data[i];
        if (!monitor || typeof monitor !== "object")
            continue;
        var name = _text(monitor.name);
        if (name === "")
            continue;

        var enabled = monitor.disabled !== true;
        var mirrorOf = _text(monitor.mirrorOf);
        rows.push({
            name: name,
            make: _text(monitor.make),
            model: _text(monitor.model),
            x: enabled ? _int(monitor.x) : 0,
            y: enabled ? _int(monitor.y) : 0,
            width: enabled ? _int(monitor.width) : 0,
            height: enabled ? _int(monitor.height) : 0,
            refresh: enabled ? _positive(monitor.refreshRate, 0) : 0,
            scale: enabled ? _positive(monitor.scale, 1) : 1,
            enabled: enabled,
            mirrorOf: mirrorOf === "none" ? "" : mirrorOf
        });
    }
    return sortOutputs(rows);
}

// The single comma-joined argument Hyprland's `monitor` keyword takes:
//
//   <name>,<mode>,<position>,<scale>[,mirror,<source>]
//
// `overrides` carries only what the caller means to change (`scale`,
// `mirrorOf`); everything else is re-stated from the row so a scale change
// never silently drops an active mirror, and vice versa. Position stays
// "auto" — omarchy's own scale and mirror scripts do the same, and a literal
// x/y here would fight the compositor's layout on every change when neither
// control means to move anything.
function hyprlandMonitorArg(row, overrides) {
    var changes = overrides || {};
    var scale = cleanScale(changes.scale !== undefined ? changes.scale : row.scale, row.width, row.height);
    var mirrorOf = changes.mirrorOf !== undefined ? _text(changes.mirrorOf) : _text(row.mirrorOf);

    var arg = row.name + "," + _hyprlandMode(row) + ",auto," + _trimNumber(scale, 5);
    if (mirrorOf !== "")
        arg += ",mirror," + mirrorOf;
    return arg;
}

function _hyprlandMode(row) {
    if (row.width <= 0 || row.height <= 0)
        return "preferred";
    var mode = row.width + "x" + row.height;
    if (row.refresh > 0)
        mode += "@" + _trimNumber(row.refresh, 5);
    return mode;
}

// ---- GPU annotation (M38 Task 9) ---------------------------------------

// The row's own meta line naming the card driving it, e.g. "NVIDIA /
// DISCRETE" for `connectorName`'s row when it matches one of `cards`'
// (GpuService.cards, or any array of gpu.js card records) connector names
// verbatim. "" when no card claims the connector, never a guess. Also ""
// whenever there is one card or fewer, since annotating every row with the
// same card is noise on a single-GPU machine, the common case (the owner's
// second laptop, the test VM).
function outputCardLabel(connectorName, cards) {
    var list = cards || [];
    if (list.length <= 1)
        return "";
    var card = Gpu.outputCard(connectorName, list);
    if (!card)
        return "";
    var vendor = Gpu.vendorName(card.vendorId) || String(card.driver || "").toUpperCase();
    return vendor + " / " + (Gpu.isDiscrete(card) ? "DISCRETE" : "INTEGRATED");
}

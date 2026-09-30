.pragma library

// The one device shape every earbuds backend normalises into (spec
// docs/superpowers/specs/2026-09-30-m77-earbuds.md), and the helpers the
// panel, bar cell and IPC read it through. No Quickshell dependency.
//
// device: { key, backend, address, name, kind: "earbuds"|"headphone",
//   connected, batteries: [battery], controls: [control], stateLine }
// battery: { id: "left"|"right"|"case"|"single", label, level, charging,
//   inEar }, where inEar is null for a component with no in-ear sensor.
// control: { key, kind: "choice"|"toggle"|"range", label, hint, section,
//   value, enabled, options: [{ value, label, icon }] | null, min, max,
//   step, unit }. `hint` is the dim second line under a toggle's label, ""
//   for none. `unit` is how a range reads beside its track (rangeText):
//   "percent" (the default, the position in its span) or "db" (the value
//   itself as signed decibels); "" on every other kind. A capability the device lacks is absent from `controls`, and an
//   adapter lists a battery only once its level is known.

function device(fields) {
    return {
        key: fields.key,
        backend: fields.backend,
        address: fields.address || "",
        name: fields.name || "",
        kind: fields.kind === "headphone" ? "headphone" : "earbuds",
        connected: fields.connected === true,
        batteries: fields.batteries || [],
        controls: fields.controls || [],
        stateLine: fields.stateLine || ""
    };
}

function choice(key, label, section, value, options) {
    return { key: key, kind: "choice", label: label, hint: "", section: section, value: value, enabled: true, options: options, min: 0, max: 0, step: 0, unit: "" };
}

function toggle(key, label, hint, section, value) {
    return { key: key, kind: "toggle", label: label, hint: hint || "", section: section, value: value === true, enabled: true, options: null, min: 0, max: 0, step: 0, unit: "" };
}

function range(key, label, section, value, min, max, step, unit) {
    return { key: key, kind: "range", label: label, hint: "", section: section, value: value, enabled: true, options: null, min: min, max: max, step: step, unit: unit === "db" ? "db" : "percent" };
}

// In ear and Charging fused " / " per DESIGN §2 item 10.
function _hint(battery) {
    var parts = [];
    if (battery.inEar === true)
        parts.push("In ear");
    if (battery.charging === true)
        parts.push("Charging");
    return parts.join(" / ");
}

function batteryRows(dev) {
    if (!dev)
        return [];
    return dev.batteries.map(function (b) {
        return { key: b.id, label: b.label, level: b.level, hint: _hint(b) };
    });
}

// The bar cell's headline: the worst bud (or the one battery a headphone
// has). The case is left out, a full case beside a near-dead bud would read
// backwards. -1 when no bud has a level.
function worstLevel(dev) {
    if (!dev)
        return -1;
    var worst = -1;
    dev.batteries.forEach(function (b) {
        if (b.id === "case")
            return;
        if (worst < 0 || b.level < worst)
            worst = b.level;
    });
    return worst;
}

var _SHORT = { left: "L", right: "R", "case": "CASE", single: "" };

function batterySummary(dev) {
    if (!dev)
        return "";
    return dev.batteries.map(function (b) {
        var tag = _SHORT[b.id];
        return tag ? tag + " " + b.level : String(b.level);
    }).join(" / ");
}

// Controls grouped by `section` in first-appearance order, the order the
// panel draws its section labels in.
function sections(dev) {
    var out = [];
    var byName = {};
    if (!dev)
        return out;
    dev.controls.forEach(function (c) {
        if (byName[c.section] === undefined) {
            byName[c.section] = out.length;
            out.push({ section: c.section, controls: [] });
        }
        out[byName[c.section]].controls.push(c);
    });
    return out;
}

function control(dev, key) {
    if (!dev)
        return null;
    for (var i = 0; i < dev.controls.length; i++)
        if (dev.controls[i].key === key)
            return dev.controls[i];
    return null;
}

function optionIndex(ctl) {
    if (!ctl || !ctl.options)
        return -1;
    for (var i = 0; i < ctl.options.length; i++)
        if (ctl.options[i].value === ctl.value)
            return i;
    return -1;
}

// raw: whatever a caller has, an IPC string included. Returns the value in
// the control's own type, or undefined when it is not one the control
// accepts: a choice outside its options, a toggle that is not on/off, a
// range that is not a number. A range value is clamped, and rounded when
// `step` is whole. `step` is the keyboard and wheel increment, not a grid a
// drag has to land on.
function coerce(ctl, raw) {
    if (!ctl || !ctl.enabled)
        return undefined;
    if (ctl.kind === "choice") {
        for (var i = 0; i < ctl.options.length; i++)
            if (String(ctl.options[i].value) === String(raw))
                return ctl.options[i].value;
        return undefined;
    }
    if (ctl.kind === "toggle") {
        if (raw === true || raw === "on" || raw === "true")
            return true;
        if (raw === false || raw === "off" || raw === "false")
            return false;
        return undefined;
    }
    if (ctl.kind === "range") {
        var n = typeof raw === "number" ? raw : Number(String(raw).trim());
        if (String(raw).trim() === "" || !isFinite(n))
            return undefined;
        n = Math.max(ctl.min, Math.min(ctl.max, n));
        return Math.round(ctl.step) === ctl.step ? Math.round(n) : n;
    }
    return undefined;
}

// The range's position as a whole percent of its span, what the panel
// prints beside the track.
function rangePercent(ctl) {
    if (!ctl || ctl.max <= ctl.min)
        return 0;
    return Math.round((ctl.value - ctl.min) / (ctl.max - ctl.min) * 100);
}

// How far along its span the value sits, 0..1, for the track's fill: min
// is empty and max full whatever sign either has, so a -6..6 band at 0 is
// half full.
function rangeFraction(ctl) {
    if (!ctl || ctl.max <= ctl.min)
        return 0;
    return Math.max(0, Math.min(1, (ctl.value - ctl.min) / (ctl.max - ctl.min)));
}

// The readout beside the track. "percent": "40%". "db": the value signed,
// "+5 dB", "0 dB", "-2 dB", whole when `step` is, with a no-break space so
// the unit never wraps off its number.
function rangeText(ctl) {
    if (!ctl)
        return "";
    if (ctl.unit !== "db")
        return rangePercent(ctl) + "%";
    var v = Math.round(ctl.step) === ctl.step ? Math.round(ctl.value) : Math.round(ctl.value * 10) / 10;
    return (v > 0 ? "+" : "") + v + "\u00a0dB";
}

// preferredKey: the key the user last selected or the device that last
// connected. Falls back to the first connected device, then the first.
function pickActive(devices, preferredKey) {
    if (!devices || devices.length === 0)
        return null;
    var i;
    for (i = 0; i < devices.length; i++)
        if (devices[i].key === preferredKey)
            return devices[i];
    for (i = 0; i < devices.length; i++)
        if (devices[i].connected)
            return devices[i];
    return devices[0];
}

// values: the Quickshell Bluetooth devices (adapter.devices.values), or []
// with no adapter. override: FORMALSHELL_SMOKE_BLUETOOTH, a JSON array of
// { address, name, connected } that replaces them outright. It exists for
// the smoke rig, whose VM has no Bluetooth controller, so a backend that
// crosses its CLI's list with BlueZ's connected devices can still be driven
// (dev/smoke.d/earbuds.sh). Unset or unparsable, the adapter is the answer.
// Every entry: { address (upper case), name, deviceName, connected }.
function bluetoothDevices(values, override) {
    if (override) {
        var raw = null;
        try {
            raw = JSON.parse(override);
        } catch (e) {
            raw = null;
        }
        if (Array.isArray(raw)) {
            return raw.filter(function (d) { return d && typeof d.address === "string"; }).map(function (d) {
                var name = typeof d.name === "string" ? d.name : "";
                return { address: d.address.toUpperCase(), name: name, deviceName: name, connected: d.connected === true };
            });
        }
    }
    var out = [];
    for (var i = 0; i < (values ? values.length : 0); i++) {
        var v = values[i];
        out.push({ address: String(v.address).toUpperCase(), name: v.name, deviceName: v.deviceName, connected: v.connected });
    }
    return out;
}

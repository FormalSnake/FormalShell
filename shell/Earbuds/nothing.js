.pragma library
.import "model.js" as Model

// Nothing and CMF adapter for the earbuds model, over `nothingctl`
// (github.com/FormalSnake/nothingctl v0.1.1). Field names are the CLI's own
// serde output: the snapshot is src/protocol/state.rs `Snapshot`, a `list
// --json` row is src/transport/mod.rs `DeviceInfo`, and `watch` prints the
// `ack`, `error` and `disconnected` lines from src/session.rs and
// src/main.rs.
//
// nothingctl is the only thing that speaks the Nothing protocol (spec
// "Safety (Nothing)"). The one channel into it is `command()` below: a line
// for `watch`'s stdin built only from the verbs `anc`, `eq`, `eq-custom`,
// `low-latency` and `spatial`, with a value taken from the device's own
// reported `available` list. Anything else comes back "" and is never
// written.

var BACKEND = "nothing";
var BINARY = "nothingctl";

// A device nothingctl refused over its model (README "Exit codes"): `watch`
// prints an error line carrying this code, then exits with UNSUPPORTED_EXIT.
// Nothing was sent to it, and retrying cannot change the answer.
var UNSUPPORTED = "unsupported-model";
var UNSUPPORTED_EXIT = 3;

var _MAC = /^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$/;
// Every name nothingctl reports is one word of lowercase ASCII. Checked on
// top of the `available` match, so a value can never carry a space or a
// line break onto stdin whatever the child printed.
var _TOKEN = /^[a-z]+$/;

// The custom EQ gain range per model base, from src/protocol/model.rs
// (`CustomEq` min_gain/max_gain). The snapshot does not carry it, so a model
// missing here gets no custom bands.
var _CUSTOM_GAIN = { B175: { min: -6, max: 6 } };
var _BANDS = [
    { key: "eq-bass", label: "Bass" },
    { key: "eq-mid", label: "Mid" },
    { key: "eq-treble", label: "Treble" }
];

var _ANC_LABEL = { off: "Off", transparency: "Transparency", high: "High", mid: "Mid", low: "Low", adaptive: "Adaptive" };
var _ANC_LINE = {
    off: "Off",
    transparency: "Transparency",
    high: "High noise cancellation",
    mid: "Mid noise cancellation",
    low: "Low noise cancellation",
    adaptive: "Adaptive"
};
var _EQ_LABEL = { rock: "Rock", electronic: "Electronic", pop: "Pop", vocals: "Vocals", classical: "Classical", custom: "Custom" };
var _SPATIAL_LABEL = { off: "Off", concert: "Concert", theatre: "Theatre" };

function validAddress(address) {
    return typeof address === "string" && _MAC.test(address);
}

function _json(text) {
    try {
        return JSON.parse(text);
    } catch (e) {
        return null;
    }
}

function listArgv() {
    return [BINARY, "list", "--json"];
}

function watchArgv(address) {
    return validAddress(address) ? [BINARY, "watch", "-d", address] : [];
}

// `list --json`: [{ address, name, connected }], every paired device that
// exposes the Nothing control service, connected or not.
function parseList(text) {
    var raw = _json(text);
    if (!Array.isArray(raw))
        return [];
    var out = [];
    raw.forEach(function (d) {
        if (d && validAddress(d.address))
            out.push({ address: d.address.toUpperCase(), name: typeof d.name === "string" ? d.name : "", connected: d.connected === true });
    });
    return out;
}

function _names(list) {
    return Array.isArray(list) ? list.filter(function (n) { return typeof n === "string" && _TOKEN.test(n); }) : [];
}

function _mode(raw) {
    if (!raw || typeof raw !== "object")
        return null;
    return { mode: typeof raw.mode === "string" ? raw.mode : null, available: _names(raw.available) };
}

function _state(raw) {
    if (!validAddress(raw.address) || !raw.model || typeof raw.model.base !== "string")
        return null;
    var eq = raw.eq && typeof raw.eq === "object" ? raw.eq : {};
    var custom = Array.isArray(eq.custom) && eq.custom.length === 3 && eq.custom.every(function (g) { return typeof g === "number" && isFinite(g); }) ? eq.custom.slice() : null;
    var battery = [];
    (Array.isArray(raw.battery) ? raw.battery : []).forEach(function (b) {
        if (b && ["left", "right", "case", "single"].indexOf(b.id) !== -1 && typeof b.level === "number")
            battery.push({ id: b.id, level: Math.max(0, Math.min(100, Math.round(b.level))), charging: b.charging === true });
    });
    return {
        address: raw.address.toUpperCase(),
        name: typeof raw.name === "string" ? raw.name : "",
        model: {
            base: raw.model.base,
            name: typeof raw.model.name === "string" ? raw.model.name : "",
            kind: raw.model.kind === "headphone" ? "headphone" : "earbuds"
        },
        battery: battery,
        anc: _mode(raw.anc),
        eq: { preset: typeof eq.preset === "string" ? eq.preset : null, available: _names(eq.available), custom: custom },
        lowLatency: typeof raw.lowLatency === "boolean" ? raw.lowLatency : null,
        spatial: _mode(raw.spatial)
    };
}

// One stdout line of `watch`. null for anything that is not one of its four
// line types, a state line with no usable address or model included.
function parseLine(line) {
    var raw = _json(String(line).trim());
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return null;
    switch (raw.type) {
    case "state":
        var state = _state(raw);
        return state ? { type: "state", state: state } : null;
    case "ack":
        return { type: "ack", cmd: typeof raw.cmd === "string" ? raw.cmd : "" };
    case "error":
        return {
            type: "error",
            code: typeof raw.code === "string" ? raw.code : "",
            modelId: typeof raw.modelId === "string" ? raw.modelId : null,
            message: typeof raw.message === "string" ? raw.message : ""
        };
    case "disconnected":
        return { type: "disconnected" };
    }
    return null;
}

// marks: address -> { seenDown }, the devices refused over their model.
// connected: the addresses BlueZ reports connected right now. A mark is
// armed once its device is seen disconnected and dropped when it is seen
// connected after that, so a refused device is tried again only after a
// real reconnect. Returns a new object.
function rearm(marks, connected) {
    var out = {};
    Object.keys(marks).forEach(function (a) {
        var up = connected.indexOf(a) !== -1;
        if (up && marks[a].seenDown)
            return;
        out[a] = { seenDown: marks[a].seenDown || !up };
    });
    return out;
}

function _options(names, labels) {
    return names.map(function (n) { return { value: n, label: labels[n] || n, icon: "" }; });
}

function _chosen(mode) {
    return mode.mode !== null && mode.available.indexOf(mode.mode) !== -1 ? mode.mode : null;
}

function _gain(state) {
    return _CUSTOM_GAIN.hasOwnProperty(state.model.base) ? _CUSTOM_GAIN[state.model.base] : null;
}

// Custom bands only while the custom preset is on: nothingctl reads the
// gains only then, and a write to them does nothing audible under another
// preset.
function _customShown(state) {
    return state.eq.preset === "custom" && state.eq.available.indexOf("custom") !== -1 && state.eq.custom !== null && _gain(state) !== null;
}

var _BATTERY_LABEL = { left: "Left", right: "Right", "case": "Case", single: "Battery" };

// failure: "" or FAILED after a refused write, shown in place of
// the listening mode until the next state line.
function normalise(state, failure) {
    var controls = [];
    if (state.anc && state.anc.available.length > 0)
        controls.push(Model.choice("anc", "Listening mode", "Listening mode", _chosen(state.anc), _options(state.anc.available, _ANC_LABEL)));
    if (state.eq.available.length > 0) {
        var preset = state.eq.available.indexOf(state.eq.preset) !== -1 ? state.eq.preset : null;
        controls.push(Model.choice("eq", "Equalizer preset", "Equalizer", preset, _options(state.eq.available, _EQ_LABEL)));
    }
    if (_customShown(state)) {
        var gain = _gain(state);
        _BANDS.forEach(function (band, i) {
            controls.push(Model.range(band.key, band.label, "Equalizer", Math.max(gain.min, Math.min(gain.max, state.eq.custom[i])), gain.min, gain.max, 1, "db"));
        });
    }
    if (state.spatial && state.spatial.available.length > 0)
        controls.push(Model.choice("spatial", "Spatial audio", "Spatial audio", _chosen(state.spatial), _options(state.spatial.available, _SPATIAL_LABEL)));
    if (state.lowLatency !== null)
        controls.push(Model.toggle("low-latency", "Low latency", "Less audio delay for games and video", "Options", state.lowLatency));
    var anc = state.anc ? _chosen(state.anc) : null;
    return Model.device({
        key: BACKEND + ":" + state.address,
        backend: BACKEND,
        address: state.address,
        name: state.name !== "" ? state.name : state.model.name,
        kind: state.model.kind,
        connected: true,
        batteries: state.battery.map(function (b) {
            return { id: b.id, label: _BATTERY_LABEL[b.id], level: b.level, charging: b.charging, inEar: null };
        }),
        controls: controls,
        stateLine: failure ? failure : anc !== null && _ANC_LINE[anc] ? _ANC_LINE[anc] : ""
    });
}

function _pick(mode, value) {
    return mode && typeof value === "string" && _TOKEN.test(value) && mode.available.indexOf(value) !== -1;
}

function _wholeGain(g, gain) {
    return typeof g === "number" && Math.round(g) === g && g >= gain.min && g <= gain.max;
}

// The `watch` stdin line (no newline) for one control change, or "" when
// the verb, the value or the device's own state does not allow it. `state`
// is that device's last parsed state.
function command(controlKey, value, state) {
    if (!state)
        return "";
    switch (controlKey) {
    case "anc":
        return _pick(state.anc, value) ? "anc " + value : "";
    case "eq":
        return _pick(state.eq, value) ? "eq " + value : "";
    case "spatial":
        return _pick(state.spatial, value) ? "spatial " + value : "";
    case "low-latency":
        return state.lowLatency !== null && typeof value === "boolean" ? "low-latency " + (value ? "on" : "off") : "";
    case "eq-bass":
    case "eq-mid":
    case "eq-treble":
        if (!_customShown(state))
            return "";
        var gain = _gain(state);
        var gains = state.eq.custom.map(function (g) { return Math.round(g); });
        gains[["eq-bass", "eq-mid", "eq-treble"].indexOf(controlKey)] = value;
        if (!gains.every(function (g) { return _wholeGain(g, gain); }))
            return "";
        return "eq-custom " + gains.join(" ");
    }
    return "";
}

// The hero line while nothingctl's last answer to a write was an error.
var FAILED = "Unable to apply the change";

.pragma library
.import "model.js" as Model

// Soundcore adapter for the earbuds model, over the `openscq30` CLI
// (github.com/Oppzippy/OpenSCQ30, cli/src/cli.rs and cli/src/cli/device.rs
// at v2.12.0). Only the documented `--json` outputs are read, since the
// plain-text ones are not stable across versions.
//
// A device appears only when it is in openscq30's own paired list (a MAC and
// a model id it was told about, not the Bluetooth pairing) and BlueZ reports
// it connected. Demo entries are skipped. A `--get` of a setting id the
// model does not have fails the whole call, so the ids to fetch come from
// `list-settings` once per connection (`capabilities`), never guessed.

var BACKEND = "soundcore";
var BINARY = "openscq30";

// ambientSoundMode's option ids, in the order the panel draws them. An id
// the model's select does not list is left out; AirplaneMode and any future
// one is never offered.
var _MODES = [
    { value: "Normal", label: "Normal", icon: "circle-off" },
    { value: "NoiseCanceling", label: "ANC", icon: "ear-off" },
    { value: "Transparency", label: "Transparency", icon: "ear" }
];

// presetEqualizerProfile has 22 options on most models. Even wrapped, with
// every label as short as "Treble reducer", that is more than four rows at
// the panel's width, so the group carries these four.
var _PRESETS = [
    { value: "SoundcoreSignature", label: "Signature", icon: "" },
    { value: "BassBooster", label: "Bass boost", icon: "" },
    { value: "TrebleBooster", label: "Treble boost", icon: "" },
    { value: "Podcast", label: "Podcast", icon: "" }
];

var _MAC = /^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$/;

function _json(text) {
    try {
        return JSON.parse(text);
    } catch (e) {
        return null;
    }
}

function validAddress(address) {
    return typeof address === "string" && _MAC.test(address);
}

// `paired-devices list --json`: [{ macAddress, model, isDemo }].
function parsePaired(text) {
    var raw = _json(text);
    if (!Array.isArray(raw))
        return [];
    var out = [];
    raw.forEach(function (p) {
        if (p && validAddress(p.macAddress))
            out.push({ address: p.macAddress.toUpperCase(), model: typeof p.model === "string" ? p.model : "", demo: p.isDemo === true });
    });
    return out;
}

// bluetooth: [{ address, name, deviceName, connected }], the Quickshell
// Bluetooth devices flattened by the backend. The paired entry a connected
// device matches, with the name BlueZ shows for it.
function connectedPaired(paired, bluetooth) {
    var out = [];
    (bluetooth || []).forEach(function (bt) {
        if (!bt.connected || !validAddress(bt.address))
            return;
        var address = bt.address.toUpperCase();
        for (var i = 0; i < paired.length; i++) {
            if (paired[i].address === address && !paired[i].demo) {
                out.push({ address: address, model: paired[i].model, name: bt.name || bt.deviceName || "" });
                return;
            }
        }
    });
    return out;
}

function _selectOptions(entry) {
    return entry && entry.setting && Array.isArray(entry.setting.options) ? entry.setting.options : [];
}

function _known(list, options) {
    return list.filter(function (o) { return options.indexOf(o.value) !== -1; });
}

// `list-settings --no-categories --json`: { <settingId>: { type, setting? } }.
// null when the text is not that object. Otherwise the parts of it this
// adapter drives: `modes` and `presets` (the offered options), `ids` (what
// to `--get`) and which battery settings the model has.
function parseCapabilities(text) {
    var raw = _json(text);
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return null;
    var caps = { modes: [], presets: [], ids: [], single: false, dual: false, hasCase: false };
    if (raw.ambientSoundMode && raw.ambientSoundMode.type === "select") {
        caps.modes = _known(_MODES, _selectOptions(raw.ambientSoundMode));
        if (caps.modes.length > 0)
            caps.ids.push("ambientSoundMode");
    }
    if (raw.presetEqualizerProfile && raw.presetEqualizerProfile.type === "optionalSelect") {
        caps.presets = _known(_PRESETS, _selectOptions(raw.presetEqualizerProfile));
        if (caps.presets.length > 0)
            caps.ids.push("presetEqualizerProfile");
    }
    ["batteryLevel", "isCharging", "batteryLevelLeft", "isChargingLeft", "batteryLevelRight", "isChargingRight", "caseBatteryLevel"].forEach(function (id) {
        if (raw[id] && raw[id].type === "information")
            caps.ids.push(id);
    });
    caps.single = raw.batteryLevel !== undefined;
    caps.dual = raw.batteryLevelLeft !== undefined || raw.batteryLevelRight !== undefined;
    caps.hasCase = raw.caseBatteryLevel !== undefined;
    return caps;
}

function pairedArgv() {
    return [BINARY, "paired-devices", "list", "--json"];
}

function settingsArgv(address) {
    return validAddress(address) ? [BINARY, "device", "-a", address, "list-settings", "--no-categories", "--json"] : [];
}

// `setting ... --json`: the gets, in order, then the sets. A failing one
// exits 1 after printing whatever was collected before it.
function settingArgv(address, tail) {
    return validAddress(address) ? [BINARY, "device", "-a", address, "setting"].concat(tail, ["--json"]) : [];
}

function getArgs(caps) {
    var out = [];
    caps.ids.forEach(function (id) { out.push("--get", id); });
    return out;
}

// `setting --get ... --json`: [{ settingId, value: { type, value } }] into
// { settingId: value }. Empty on anything else.
function parseValues(text) {
    var raw = _json(text);
    var out = {};
    if (!Array.isArray(raw))
        return out;
    raw.forEach(function (row) {
        if (row && typeof row.settingId === "string" && row.value && typeof row.value === "object")
            out[row.settingId] = row.value.value;
    });
    return out;
}

// A battery information setting reads "<step>/<max>", "4/5". openscq30 rounds
// down when it prints the percentage, so this does too. -1 when unknown.
function _level(text) {
    var m = /^(\d+)\/(\d+)$/.exec(String(text));
    if (!m || Number(m[2]) === 0)
        return -1;
    return Math.min(100, Math.floor(Number(m[1]) * 100 / Number(m[2])));
}

function _batteries(caps, values) {
    var out = [];
    function add(id, label, levelId, chargingId) {
        var level = levelId in values ? _level(values[levelId]) : -1;
        if (level < 0)
            return;
        out.push({ id: id, label: label, level: level, charging: values[chargingId] === "Yes", inEar: null });
    }
    add("left", "Left", "batteryLevelLeft", "isChargingLeft");
    add("right", "Right", "batteryLevelRight", "isChargingRight");
    add("case", "Case", "caseBatteryLevel", "");
    add("single", "Battery", "batteryLevel", "isCharging");
    return out;
}

function _choose(options, value) {
    for (var i = 0; i < options.length; i++)
        if (options[i].value === value)
            return value;
    return null;
}

var _MODE_LINE = { Normal: "Normal", NoiseCanceling: "Noise cancellation", Transparency: "Transparency" };

// info: { address, model, name } from connectedPaired. values may be {} when
// the last read failed, which lists the device with no controls rather than
// hiding one BlueZ says is connected.
function normalise(info, caps, values) {
    var controls = [];
    var mode = null;
    if (caps.modes.length > 0 && "ambientSoundMode" in values) {
        mode = _choose(caps.modes, values.ambientSoundMode);
        controls.push(Model.choice("mode", "Listening mode", "Listening mode", mode, caps.modes));
    }
    if (caps.presets.length > 0 && "presetEqualizerProfile" in values)
        controls.push(Model.choice("eq", "Equalizer preset", "Equalizer", _choose(caps.presets, values.presetEqualizerProfile), caps.presets));
    return Model.device({
        key: BACKEND + ":" + info.address,
        backend: BACKEND,
        address: info.address,
        name: info.name !== "" ? info.name : "Soundcore",
        kind: caps.single && !caps.dual ? "headphone" : "earbuds",
        connected: true,
        batteries: _batteries(caps, values),
        controls: controls,
        stateLine: mode !== null ? _MODE_LINE[mode] : ""
    });
}

// The `--set` arguments for one control, or [] for anything outside what the
// model offers. `caps` is that device's own capabilities.
function command(controlKey, value, caps) {
    if (!caps)
        return [];
    if (controlKey === "mode" && _choose(caps.modes, value) !== null)
        return ["--set", "ambientSoundMode=" + value];
    if (controlKey === "eq" && _choose(caps.presets, value) !== null)
        return ["--set", "presetEqualizerProfile=" + value];
    return [];
}

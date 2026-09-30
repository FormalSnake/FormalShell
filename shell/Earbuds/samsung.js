.pragma library
.import "model.js" as Model

// Samsung Galaxy Buds adapter for the earbuds model, over the `earbuds` CLI
// (github.com/JojiiOfficial/LiveBudsCli, nixpkgs `earbuds`). The CLI is a
// client of its own background daemon and starts it on any command, and that
// daemon acts on its own (auto-pause over MPRIS, PulseAudio sink switching),
// so the backend runs it only for a device BlueZ reports connected and whose
// name is a Galaxy Buds one (the daemon itself picks devices by name and the
// SPP uuid, src/daemon/bluetooth/bt_connection_listener.rs).

var BACKEND = "samsung";
var BINARY = "earbuds";

var _MAC = /^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$/;

function validAddress(address) {
    return typeof address === "string" && _MAC.test(address);
}

// bluetooth: [{ address, name, deviceName, connected }]. deviceName is the
// name the buds report, name the alias the user may have changed.
function connectedBuds(bluetooth) {
    var out = [];
    (bluetooth || []).forEach(function (bt) {
        if (!bt.connected || !validAddress(bt.address))
            return;
        if (/^galaxy buds/i.test(bt.deviceName || "") || /^galaxy buds/i.test(bt.name || ""))
            out.push({ address: bt.address.toUpperCase(), name: bt.name || bt.deviceName || "" });
    });
    return out;
}

// -q keeps "Daemon started successfully" off stdout, -s picks the device.
function argv(address, tail) {
    return validAddress(address) ? [BINARY, "-q", "-s", address].concat(tail) : [];
}

function statusArgv(address) {
    return argv(address, ["status", "-o", "json"]);
}

// Per model, from galaxy_buds_rs' Model::get_features (0.2.11) and the
// daemon's get_max_ambientsound_volume_level: whether it has ANC, and the
// top ambient level (0 for no ambient control). A model outside this table
// gets batteries and the equalizer only.
var _MODELS = {
    Buds: { name: "Galaxy Buds", anc: false, ambient: 3 },
    BudsPlus: { name: "Galaxy Buds+", anc: false, ambient: 4 },
    BudsLive: { name: "Galaxy Buds Live", anc: true, ambient: 0 },
    BudsPro: { name: "Galaxy Buds Pro", anc: true, ambient: 0 },
    BudsPro2: { name: "Galaxy Buds Pro 2", anc: true, ambient: 0 },
    Buds2: { name: "Galaxy Buds 2", anc: true, ambient: 3 },
    Buds3Pro: { name: "Galaxy Buds3 Pro", anc: true, ambient: 0 }
};

// EqualizerType's wire numbers (galaxy_buds_rs bud_property.rs) and the
// word `earbuds set equalizer` takes for each.
var _EQ = [
    { value: "normal", label: "Normal", icon: "" },
    { value: "bass", label: "Bass", icon: "" },
    { value: "soft", label: "Soft", icon: "" },
    { value: "dynamic", label: "Dynamic", icon: "" },
    { value: "clear", label: "Clear", icon: "" },
    { value: "treble", label: "Treble", icon: "" }
];

// Placement's wire numbers: 1 in ear, 2 outside, 3 in the open case, 4 in
// the closed case.
var _EAR = 1;

function _num(v, fallback) {
    return typeof v === "number" && isFinite(v) ? v : fallback;
}

// `status -o json` prints the daemon's response as one JSON line:
// { status, device, status_message, payload }. A "No connected device found"
// error, or anything unparseable, is { ok: false }. Text before the first
// line starting with "{" is dropped.
function parseStatus(text) {
    var bad = { ok: false, message: "" };
    var start = String(text).search(/^\{/m);
    if (start < 0)
        return bad;
    var raw;
    try {
        raw = JSON.parse(String(text).slice(start).split("\n")[0]);
    } catch (e) {
        return bad;
    }
    if (!raw || raw.status !== "success" || !raw.payload || typeof raw.payload !== "object") {
        bad.message = raw && typeof raw.status_message === "string" ? raw.status_message : "";
        return bad;
    }
    var p = raw.payload;
    return {
        ok: true,
        address: typeof p.address === "string" ? p.address : "",
        ready: p.ready === true,
        model: typeof p.model === "string" ? p.model : "",
        battLeft: _num(p.batt_left, -1),
        battRight: _num(p.batt_right, -1),
        battCase: _num(p.batt_case, -1),
        placementLeft: _num(p.placement_left, 0),
        placementRight: _num(p.placement_right, 0),
        equalizer: _num(p.equalizer_type, -1),
        anc: p.noise_reduction === true,
        ambientEnabled: p.ambient_sound_enabled === true,
        ambientVolume: _num(p.ambient_sound_volume, 0),
        extraHigh: p.extra_high_ambient_volume === true
    };
}

function _bud(id, label, level, placement) {
    // 3 and 4 are the case placements, where the buds charge.
    return { id: id, label: label, level: level, charging: placement === 3 || placement === 4, inEar: placement === _EAR };
}

function _batteries(s) {
    var out = [];
    if (s.battLeft >= 0 && s.battLeft <= 100)
        out.push(_bud("left", "Left", s.battLeft, s.placementLeft));
    if (s.battRight >= 0 && s.battRight <= 100)
        out.push(_bud("right", "Right", s.battRight, s.placementRight));
    // The CLI itself shows the case only while a bud is in it: with both
    // buds out its level is not reported.
    var inCase = [3, 4];
    if (s.battCase >= 0 && s.battCase <= 100 && (inCase.indexOf(s.placementLeft) !== -1 || inCase.indexOf(s.placementRight) !== -1))
        out.push({ id: "case", label: "Case", level: s.battCase, charging: false, inEar: null });
    return out;
}

function _ambientLevel(s, top) {
    if (!s.ambientEnabled)
        return 0;
    return Math.min(top, s.extraHigh ? 4 : s.ambientVolume);
}

// `name` is what BlueZ shows for the device. A status the daemon has not
// finished the handshake for (ready false) has no levels to show.
function normalise(status, name) {
    if (!status.ok || !status.ready || !validAddress(status.address))
        return [];
    var model = _MODELS.hasOwnProperty(status.model) ? _MODELS[status.model] : { name: "Galaxy Buds", anc: false, ambient: 0 };
    var controls = [];
    if (model.anc)
        controls.push(Model.toggle("anc", "Noise cancellation", "", "Listening mode", status.anc));
    var level = -1;
    if (model.ambient > 0) {
        var options = [];
        for (var i = 0; i <= model.ambient; i++)
            options.push({ value: i, label: i === 0 ? "Off" : String(i), icon: "" });
        level = _ambientLevel(status, model.ambient);
        controls.push(Model.choice("ambient", "Ambient sound", "Listening mode", level, options));
    }
    controls.push(Model.choice("eq", "Equalizer", "Equalizer", status.equalizer >= 0 && status.equalizer < _EQ.length ? _EQ[status.equalizer].value : null, _EQ));
    var line = "";
    if (model.anc || model.ambient > 0)
        line = status.anc && model.anc ? "Noise cancellation" : level > 0 ? "Ambient sound" : "Off";
    return [Model.device({
        key: BACKEND + ":" + status.address.toUpperCase(),
        backend: BACKEND,
        address: status.address.toUpperCase(),
        name: name !== "" ? name : model.name,
        kind: "earbuds",
        connected: true,
        batteries: _batteries(status),
        controls: controls,
        stateLine: line
    })];
}

// The CLI arguments after the device flags, or [] for anything outside this
// list. Ambient tops out at 4 here; the daemon refuses a level past the
// model's own maximum.
function command(controlKey, value) {
    switch (controlKey) {
    case "anc":
        return typeof value === "boolean" ? [value ? "enable" : "disable", "anc"] : [];
    case "ambient":
        return (typeof value === "number" && value >= 0 && value <= 4 && Math.round(value) === value) ? ["set", "ambientsound", String(value)] : [];
    case "eq":
        return _EQ.some(function (e) { return e.value === value; }) ? ["set", "equalizer", value] : [];
    default:
        return [];
    }
}

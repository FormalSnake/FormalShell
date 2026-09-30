.pragma library
.import "model.js" as Model

// AirPods adapter for the earbuds model: the omarchy-pods librepods
// daemon's status.json in, the daemon's control-socket verbs out. Talks
// only to the wire shape the daemon publishes, nothing here is ported from
// that project's own (GPL) source, this is an independent reimplementation
// of the documented contract (plan's research block,
// docs/superpowers/plans/2026-08-18-m29-device-panels.md).
//
// `left`/`right`/`case` are absent from the daemon's JSON entirely until a
// battery packet has arrived, never present with `available:false`, so
// every parse path below returns a complete default shape rather than
// leaving a caller to guard against `undefined`. `connected:false` does
// not mean nothing is known: battery keeps arriving over BLE adverts while
// the buds sit in the case, which is why normalise() keeps a device with a
// known level and the link down.

var BACKEND = "airpods";

// noise_mode wire values (daemon's status.json, and the noise:<mode>
// control verb suffixes).
var NoiseMode = {
    Off: 0,
    Anc: 1,
    Transparency: 2,
    Adaptive: 3
};

var _NOISE_MODE_KEY = { 0: "off", 1: "anc", 2: "transparency", 3: "adaptive" };

var _NOISE_MODE_META = {
    "-1": "Unknown",
    "0": "Off",
    "1": "Noise cancellation",
    "2": "Transparency",
    "3": "Adaptive"
};

// ear_detection_behavior's own numbering: 0 one out, 1 both out, 2 never.
var _EAR_KEY = ["one", "both", "off"];

function _defaultPod() {
    return { available: false, level: -1, charging: false, inEar: false };
}

function _defaultCase() {
    return { available: false, level: -1, charging: false };
}

function _defaultStatus() {
    return {
        ok: false,
        connected: false,
        deviceName: "",
        modelName: "",
        isPro: false,
        supportsOff: true,
        noiseMode: -1,
        left: _defaultPod(),
        right: _defaultPod(),
        caseBattery: _defaultCase(),
        conversationalAwareness: false,
        adaptiveNoiseLevel: 0,
        oneBudAnc: false,
        earDetection: 0,
        lidState: 2
    };
}

function _parsePod(raw) {
    if (!raw || typeof raw !== "object")
        return _defaultPod();
    return {
        available: raw.available === true,
        level: typeof raw.level === "number" ? raw.level : -1,
        charging: raw.charging === true,
        inEar: raw.in_ear === true
    };
}

function _parseCase(raw) {
    if (!raw || typeof raw !== "object")
        return _defaultCase();
    return {
        available: raw.available === true,
        level: typeof raw.level === "number" ? raw.level : -1,
        charging: raw.charging === true
    };
}

// text: one line of the daemon's own JSON, or "" / malformed / a foreign
// schema_version. Every one of those returns the same complete default
// shape (ok:false) rather than throwing or handing back a partial object:
// a caller never null-checks a field, it checks `ok` once.
function parseStatus(text) {
    var result = _defaultStatus();
    if (!text)
        return result;

    var raw;
    try {
        raw = JSON.parse(text);
    } catch (e) {
        return result;
    }
    if (!raw || typeof raw !== "object" || raw.schema_version !== 1)
        return result;

    result.ok = true;
    result.connected = raw.connected === true;
    result.deviceName = typeof raw.device_name === "string" ? raw.device_name : "";
    result.modelName = typeof raw.model_name === "string" ? raw.model_name : "";
    result.isPro = raw.is_pro_series === true;
    // Missing key defaults to supporting Off, only Pro 3 sets this false.
    result.supportsOff = raw.supports_noise_off !== false;
    result.noiseMode = typeof raw.noise_mode === "number" ? raw.noise_mode : -1;
    result.left = _parsePod(raw.left);
    result.right = _parsePod(raw.right);
    result.caseBattery = _parseCase(raw["case"]);
    result.conversationalAwareness = raw.conversational_awareness === true;
    result.adaptiveNoiseLevel = typeof raw.adaptive_noise_level === "number" ? raw.adaptive_noise_level : 0;
    result.oneBudAnc = raw.one_bud_anc_mode === true;
    result.earDetection = typeof raw.ear_detection_behavior === "number" ? raw.ear_detection_behavior : 0;
    result.lidState = typeof raw.lid_state === "number" ? raw.lid_state : 2;
    return result;
}

function lidLabel(n) {
    switch (n) {
    case 0: return "Lid open";
    case 1: return "Lid closed";
    default: return "";
    }
}

function noiseModeLabel(n) {
    var label = _NOISE_MODE_META[String(n)];
    return label !== undefined ? label : "Unknown";
}

// The hero meta line: the noise mode when connected, else "Not
// connected", fused with lid state when known, " / " per §2 item 10.
function stateLine(status) {
    var parts = [status.connected ? noiseModeLabel(status.noiseMode) : "Not connected"];
    var lid = lidLabel(status.lidState);
    if (lid !== "")
        parts.push(lid);
    return parts.join(" / ");
}

function _batteries(status) {
    var out = [];
    if (status.left.available && status.left.level >= 0)
        out.push({ id: "left", label: "Left", level: status.left.level, charging: status.left.charging, inEar: status.left.inEar });
    if (status.right.available && status.right.level >= 0)
        out.push({ id: "right", label: "Right", level: status.right.level, charging: status.right.charging, inEar: status.right.inEar });
    if (status.caseBattery.available && status.caseBattery.level >= 0)
        out.push({ id: "case", label: "Case", level: status.caseBattery.level, charging: status.caseBattery.charging, inEar: null });
    return out;
}

// Listening mode and the two Pro toggles need the L2CAP link up to mean
// anything. Off only exists while the device supports it (Pro 3 dropped
// it), Adaptive and its level only on Pro models. Ear detection is
// host-side daemon policy, so it stays whenever the device is known at
// all, in-case included.
function _controls(status) {
    var out = [];
    if (status.connected) {
        var modes = [];
        if (status.supportsOff)
            modes.push({ value: "off", label: "Off", icon: "circle-off" });
        modes.push({ value: "anc", label: "ANC", icon: "ear-off" });
        modes.push({ value: "transparency", label: "Transparency", icon: "ear" });
        if (status.isPro)
            modes.push({ value: "adaptive", label: "Adaptive", icon: "audio-waveform" });
        var mode = _NOISE_MODE_KEY[status.noiseMode];
        out.push(Model.choice("noise", "Listening mode", "Listening mode", mode !== undefined ? mode : null, modes));
        if (status.noiseMode === NoiseMode.Adaptive)
            out.push(Model.range("adaptive", "Adaptive noise", "Listening mode", status.adaptiveNoiseLevel, 0, 100, 5));
        if (status.isPro) {
            out.push(Model.toggle("ca", "Conversation awareness", "Lowers volume when you talk", "Options", status.conversationalAwareness));
            out.push(Model.toggle("onebud", "One-bud ANC", "Keeps ANC with one pod in", "Options", status.oneBudAnc));
        }
    }
    var ear = _EAR_KEY[status.earDetection];
    out.push(Model.choice("ear", "Ear detection", "Ear detection", ear !== undefined ? ear : null, [
        { value: "one", label: "One", icon: "" },
        { value: "both", label: "Both", icon: "" },
        { value: "off", label: "Off", icon: "" }
    ]));
    return out;
}

// A live daemon that has never seen a battery packet and reports the link
// down knows of no device: the file existing only proves the daemon is up.
function normalise(status) {
    if (!status.ok)
        return [];
    var batteries = _batteries(status);
    if (!status.connected && batteries.length === 0)
        return [];
    return [Model.device({
        key: BACKEND,
        backend: BACKEND,
        address: "",
        name: status.deviceName !== "" ? status.deviceName : "AirPods",
        kind: "earbuds",
        connected: status.connected,
        batteries: batteries,
        controls: _controls(status),
        stateLine: stateLine(status)
    })];
}

// The daemon socket's own verbs (daemon/librepods-ctl.cpp's usage text,
// read-reference only). connect/disconnect/forget are deliberately left
// out: those shell out to bluetoothctl, and that job belongs to the
// Bluetooth panel. Returns "" for anything outside this list.
function command(controlKey, value) {
    switch (controlKey) {
    case "noise":
        return ["off", "anc", "transparency", "adaptive"].indexOf(value) !== -1 ? "noise:" + value : "";
    case "adaptive":
        return (typeof value === "number" && value >= 0 && value <= 100) ? "adaptive:" + Math.round(value) : "";
    case "ca":
        return typeof value === "boolean" ? (value ? "ca:on" : "ca:off") : "";
    case "onebud":
        return typeof value === "boolean" ? (value ? "onebud:on" : "onebud:off") : "";
    case "ear":
        return _EAR_KEY.indexOf(value) !== -1 ? "ear:" + value : "";
    default:
        return "";
    }
}

.pragma library

// Pure model for the AirPods panel (M29 Task 1). No Quickshell dependency,
// so it's testable head-on against fixture status lines (mirrors
// Bluetooth/model.js). Talks only to the wire shape the omarchy-pods
// librepods daemon publishes — nothing here is ported from that project's
// own (GPL) source, this is an independent reimplementation of the
// documented contract (plan's research block,
// docs/superpowers/plans/2026-08-18-m29-device-panels.md).
//
// `left`/`right`/`case` are absent from the daemon's JSON entirely until a
// battery packet has arrived — never present with `available:false` — so
// every parse path below returns a complete default shape rather than
// leaving a caller to guard against `undefined`. `connected:false` does
// not mean nothing is known: battery keeps arriving over BLE adverts while
// the buds sit in the case, which is why batteryRows() gates on a known
// level rather than on the link being up.

// noise_mode wire values (daemon's status.json, and the noise:<mode>
// control verb suffixes).
var NoiseMode = {
    Off: 0,
    Anc: 1,
    Transparency: 2,
    Adaptive: 3
};

var _NOISE_MODE_TITLE = {
    0: "Off",
    1: "Noise Cancellation",
    2: "Transparency",
    3: "Adaptive"
};

var _NOISE_MODE_META = {
    "-1": "UNKNOWN",
    "0": "OFF",
    "1": "NOISE CANCELLATION",
    "2": "TRANSPARENCY",
    "3": "ADAPTIVE"
};

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
// shape (ok:false) rather than throwing or handing back a partial object
// — a caller never null-checks a field, it checks `ok` once.
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
    // Missing key defaults to supporting Off — only Pro 3 sets this false.
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

// One component's hint, fused " / " per DESIGN §2 item 10 (meta pairs
// never take a colon). Case has no in-ear concept, so hasInEar is false
// for it and only CHARGING can ever appear.
function _hint(inEar, charging, hasInEar) {
    var parts = [];
    if (hasInEar && inEar)
        parts.push("IN EAR");
    if (charging)
        parts.push("CHARGING");
    return parts.join(" / ");
}

// The BATTERY section's rows — one per component with a known level.
// Empty array when nothing has reported a level yet (fresh daemon), which
// is the panel's cue to skip the whole section rather than draw an empty
// one.
function batteryRows(status) {
    var rows = [];
    if (status.left.available && status.left.level >= 0)
        rows.push({ key: "left", label: "Left", level: status.left.level, hint: _hint(status.left.inEar, status.left.charging, true) });
    if (status.right.available && status.right.level >= 0)
        rows.push({ key: "right", label: "Right", level: status.right.level, hint: _hint(status.right.inEar, status.right.charging, true) });
    if (status.caseBattery.available && status.caseBattery.level >= 0)
        rows.push({ key: "case", label: "Case", level: status.caseBattery.level, hint: _hint(false, status.caseBattery.charging, false) });
    return rows;
}

// The LISTENING MODE section's rows. Off only exists while the device
// supports it (Pro 3 dropped it); Adaptive only exists on Pro models.
// Independent of `connected` — the panel itself decides whether to gate
// the whole section on the link being up.
function modesFor(status) {
    var modes = [];
    if (status.supportsOff)
        modes.push({ key: "off", label: _NOISE_MODE_TITLE[NoiseMode.Off], verb: "noise:off", active: status.noiseMode === NoiseMode.Off });
    modes.push({ key: "anc", label: _NOISE_MODE_TITLE[NoiseMode.Anc], verb: "noise:anc", active: status.noiseMode === NoiseMode.Anc });
    modes.push({ key: "transparency", label: _NOISE_MODE_TITLE[NoiseMode.Transparency], verb: "noise:transparency", active: status.noiseMode === NoiseMode.Transparency });
    if (status.isPro)
        modes.push({ key: "adaptive", label: _NOISE_MODE_TITLE[NoiseMode.Adaptive], verb: "noise:adaptive", active: status.noiseMode === NoiseMode.Adaptive });
    return modes;
}

function earDetectionLabel(n) {
    switch (n) {
    case 0: return "PAUSE WHEN ONE IS OUT";
    case 1: return "WHEN BOTH ARE OUT";
    case 2: return "NEVER";
    default: return "UNKNOWN";
    }
}

function lidLabel(n) {
    switch (n) {
    case 0: return "LID OPEN";
    case 1: return "LID CLOSED";
    default: return "";
    }
}

function noiseModeLabel(n) {
    var label = _NOISE_MODE_META[String(n)];
    return label !== undefined ? label : "UNKNOWN";
}

// The hero meta line: the link state (noise mode when connected, else
// NOT CONNECTED) fused with lid state when known, " / " per §2 item 10.
function stateLine(status) {
    var parts = [status.connected ? noiseModeLabel(status.noiseMode) : "NOT CONNECTED"];
    var lid = lidLabel(status.lidState);
    if (lid !== "")
        parts.push(lid);
    return parts.join(" / ");
}

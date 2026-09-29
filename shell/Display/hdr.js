.pragma library
.import "outputs.js" as Outputs

// Pure HDR model for HdrService: what an output's EDID says about HDR, what
// to persist when it is switched on, and which outputs a shell start has to
// put back. No Process and no Quickshell here (tests/tst_display_hdr.qml).
//
// Hyprland 0.56 does not put HDR support in `monitors -j`, only the applied
// `colorManagementPreset`. It decides support itself in
// CMonitor::supportsHDR(): the EDID's CTA-861 colorimetry block lists
// BT.2020 RGB and its HDR static metadata block lists the PQ (SMPTE ST 2084)
// EOTF. An unsupported output silently falls back to sRGB when handed
// `cm = hdr`, so support is read from the EDID beforehand rather than found
// out by applying the rule.

var EXT_COLORIMETRY = 5;
var EXT_HDR_STATIC = 6;

function _bytes(hexText) {
    var out = [];
    var tokens = String(hexText || "").split(/\s+/);
    for (var i = 0; i < tokens.length; i++) {
        if (/^[0-9a-fA-F]{2}$/.test(tokens[i]))
            out.push(parseInt(tokens[i], 16));
    }
    return out;
}

// `od -An -tx1 -v` text of /sys/class/drm/<card>-<connector>/edid.
// `present` is false for an empty or truncated file, which is what the
// kernel exposes for a connector with no EDID (the VM's vkms).
function parseEdid(hexText) {
    var bytes = _bytes(hexText);
    var result = { present: false, wide: false, pq: false, maxNits: 0 };
    if (bytes.length < 128)
        return result;
    result.present = true;

    var blocks = Math.floor(bytes.length / 128);
    for (var b = 1; b < blocks; b++) {
        var base = b * 128;
        if (bytes[base] !== 0x02)
            continue;
        var end = Math.min(bytes[base + 2], 127);
        var i = base + 4;
        while (i < base + end) {
            var tag = bytes[i] >> 5;
            var len = bytes[i] & 0x1f;
            if (tag === 7 && len >= 2) {
                var ext = bytes[i + 1];
                if (ext === EXT_COLORIMETRY)
                    result.wide = (bytes[i + 2] & 0x80) !== 0;
                else if (ext === EXT_HDR_STATIC) {
                    result.pq = (bytes[i + 2] & 0x04) !== 0;
                    if (len >= 4)
                        result.maxNits = Math.round(50 * Math.pow(2, bytes[i + 4] / 32));
                }
            }
            i += len + 1;
        }
    }
    return result;
}

// The EDID reader's output: one `@@<output name>` line per connector, then
// its `od` hex. Returns { name: parseEdid(...) }; an output with no line was
// not found under /sys/class/drm at all.
function parseDump(text) {
    var out = {};
    var name = null;
    var hex = "";
    var lines = String(text || "").split("\n");
    for (var i = 0; i <= lines.length; i++) {
        var line = i < lines.length ? lines[i] : "@@";
        if (line.indexOf("@@") === 0) {
            if (name !== null && !(out[name] && out[name].present))
                out[name] = parseEdid(hex);
            name = line.slice(2).trim();
            hex = "";
        } else {
            hex += line + " ";
        }
    }
    return out;
}

// { supported, reason }. `edid` undefined means the reader has not answered
// yet or found no connector node.
function verdict(edid) {
    if (!edid || !edid.present)
        return { supported: false, reason: "No EDID" };
    if (!edid.pq)
        return { supported: false, reason: "No HDR in EDID" };
    if (!edid.wide)
        return { supported: false, reason: "No wide gamut in EDID" };
    return { supported: true, reason: "" };
}

function isOn(row) {
    return !!row && Outputs.isHdrPreset(row.cm);
}

// The colour settings to restore on the way out. An HDR preset is never
// recorded as the prior, or a shell restart in HDR could not turn it off.
function priorOf(row) {
    return {
        cm: Outputs.isHdrPreset(row.cm) || !row.cm ? "srgb" : row.cm,
        bitdepth: row.tenBit ? 10 : 8,
        sdrbrightness: row.sdrBrightness > 0 ? row.sdrBrightness : 1,
        sdrsaturation: row.sdrSaturation > 0 ? row.sdrSaturation : 1
    };
}

function onColor(brightness, saturation) {
    return { cm: "hdr", bitdepth: 10, sdrbrightness: brightness, sdrsaturation: saturation };
}

function offColor(prior) {
    var p = prior || {};
    return {
        cm: Outputs.isHdrPreset(p.cm) || !p.cm ? "srgb" : p.cm,
        bitdepth: p.bitdepth === 10 ? 10 : 8,
        sdrbrightness: p.sdrbrightness > 0 ? p.sdrbrightness : 1,
        sdrsaturation: p.sdrsaturation > 0 ? p.sdrsaturation : 1
    };
}

// state.json's `hdr`: { "<output>": { prior } }, an entry present while the
// user wants that output in HDR. Always a fresh object, so the adapter's
// var property notices the assignment.
function stateOf(saved) {
    var out = {};
    if (saved && typeof saved === "object") {
        for (var name in saved) {
            if (saved[name] && typeof saved[name] === "object")
                out[name] = saved[name];
        }
    }
    return out;
}

function withOutput(saved, name, prior) {
    var out = stateOf(saved);
    out[name] = { prior: prior };
    return out;
}

function withoutOutput(saved, name) {
    var out = stateOf(saved);
    delete out[name];
    return out;
}

// Outputs a shell start (or a config reload that reset the rules) has to put
// back in HDR: wanted in state, present and lit, supported, not in HDR now,
// and not already tried since the last reset. `verdicts` is { name: verdict }.
function pendingReapply(saved, rows, verdicts, tried) {
    var wanted = stateOf(saved);
    var names = [];
    for (var i = 0; i < (rows || []).length; i++) {
        var row = rows[i];
        if (wanted[row.name] === undefined || !row.enabled || isOn(row))
            continue;
        if (!verdicts[row.name] || !verdicts[row.name].supported)
            continue;
        if ((tried || {})[row.name])
            continue;
        names.push(row.name);
    }
    return names;
}

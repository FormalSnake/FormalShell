.pragma library

// Pure model for the AirPlay receiver (M75 Task 6, plan at
// docs/superpowers/plans/2026-09-28-m75-iphone.md). No Quickshell access, so
// tst_airplay_model.qml drives it head-on with UxPlay's own file and log
// shapes.
//
// Facts checked against FDH2/UxPlay's source at HEAD (2026-09-28), not
// guessed: `-md <fn>` overwrites the whole file on every DMAP metadata
// update (uxplay.cpp audio_set_metadata()), one `Label: value\n` line per
// field the update actually carried (process_metadata()), "no data\n" at
// the start of a session and on the placeholder reset that follows a
// connect. So a field absent from the latest read is absent from that
// update, not carried over from a previous one: parseMetadata never merges
// across reads. `-ca <fn>` overwrites the same way, but every reset also
// writes a fixed 95-byte placeholder PNG (a single white pixel) before any
// real art arrives, so a cover is only real once the file's size departs
// from that exact count. `-dacp <fn>` exists only while a client is
// connected (export_dacp()/conn_destroy()), a presence check, not something
// this model ever needs to read. Every logged line UxPlay prints is INFO
// level with no prefix (logger.h's LOGGER_INFO, uxplay.cpp's log(): only
// levels 0-3 get an "*** ERROR: " prefix), and INFO is the default level, so
// both lines below appear on stdout with no flag needed.

var COVER_PLACEHOLDER_BYTES = 95;

var _METADATA_LINE = /^([A-Za-z][A-Za-z ]*): (.*)$/;
var _METADATA_KEYS = { "Title": "title", "Artist": "artist", "Album": "album", "Genre": "genre" };

// report_client_request()'s own format string: "connection request from %s
// (%s) with deviceID = %s\n" (name, model, deviceID); name is whatever the
// phone advertises as its own device name.
var _CONNECTED_LINE = /^connection request from (.+) \((.+)\) with deviceID = (.+)$/;

// conn_destroy()'s LOGI text; matched by substring since the two sites that
// log it (uxplay.cpp:579, :2657) disagree on the exact "***ERROR"/"*** ERROR"
// spacing, both literal message text rather than a logger-added prefix.
var _DISCONNECTED_MARK = "lost connection with client";

// Every field this update actually reported, "" for the rest: a caller that
// wants "unknown" to read as the empty string already gets that for free,
// and a genuinely blank field ("Artist: ") reads the same way, which is the
// file's own limit, not this parser's.
function parseMetadata(text) {
    var out = { title: "", artist: "", album: "", genre: "" };
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(_METADATA_LINE);
        if (!m)
            continue;
        var field = _METADATA_KEYS[m[1]];
        if (field)
            out[field] = m[2];
    }
    return out;
}

// A cover file this size is always the reset placeholder (a fixed 95-byte
// PNG UxPlay writes verbatim), never a real one: no track ever legitimately
// compresses to exactly that count.
function isPlaceholderCover(byteSize) {
    return byteSize === COVER_PLACEHOLDER_BYTES;
}

// One stdout line to a connect/disconnect/error event, or null for a line
// that reports neither (the great majority: startup banners, per-packet
// debug noise at higher log levels, etc).
function parseLine(line) {
    var text = String(line || "").trim();
    if (text === "")
        return null;
    var m = text.match(_CONNECTED_LINE);
    if (m)
        return { type: "connected", name: m[1], model: m[2], deviceId: m[3] };
    if (text.indexOf(_DISCONNECTED_MARK) >= 0)
        return { type: "disconnected" };
    if (text.indexOf("*** ERROR") === 0 || text.indexOf("***ERROR") === 0)
        return { type: "error", message: text };
    return null;
}

// airplay.name, or this machine's hostname once the `hostname` probe
// answers, or the shell's own name while neither is known yet -- the same
// fallback chain LocalsendService's `alias` uses for the same reason (UxPlay
// needs a name up front, at spawn, so there's no "wait for it" here).
function resolveName(configured, hostname) {
    if (configured !== "")
        return configured;
    return hostname !== "" ? hostname : "FormalShell";
}

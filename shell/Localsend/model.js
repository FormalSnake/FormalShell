.pragma library

// Pure model for LocalSend (M75 Task 5, plan at
// docs/superpowers/plans/2026-09-28-m75-iphone.md). No Quickshell access, so
// tst_localsend_model.qml drives it head-on with the CLI's own stdout/stderr
// shapes.
//
// The CLI is 0w0mewo/localsend-cli (Go, rev 7865fb1c, see
// nix/localsend-cli.nix for why this one over the official Rust `cli/`
// crate). `scan -t <seconds>` prints one line per discovered peer to
// stdout under a "Found Devices:" header, or "No device found" to stderr
// when nothing answered (scan.go's own Fprintf calls). `send`/`recv` log
// every event through Go's log/slog default text handler, one
// space-separated `key=value` pair per field, string values quoted only
// when they contain a space (slog's own quoting rule) -- that shape is
// what parseSlogLine reads, not a fixed field list.

// --- scan ------------------------------------------------------------------

// "\tName: <alias>, Version: <ver>, Address: <ip>:<port>, Protocol: <proto>"
// (cmd/scan/scan.go's Fprintf), one line per peer, following the "Found
// Devices:" header line that the loop below simply doesn't match.
var _SCAN_LINE_RE = /^\tName: (.*), Version: (.*), Address: ([^:]+):(\d+), Protocol: (.*)$/;

function parseScan(stdout) {
    var peers = [];
    var lines = String(stdout || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(_SCAN_LINE_RE);
        if (!m)
            continue;
        peers.push({
            name: m[1],
            version: m[2],
            ip: m[3],
            port: Number(m[4]),
            protocol: m[5]
        });
    }
    return peers;
}

// Exact-name match against the last scan's results, null when the device
// has gone quiet since (out of range, or the scan simply predates it).
function resolvePeer(peers, name) {
    var list = peers || [];
    for (var i = 0; i < list.length; i++) {
        if (list[i].name === name)
            return list[i];
    }
    return null;
}

// --- slog lines --------------------------------------------------------

var _KV_RE = /([A-Za-z_][\w.]*)=("(?:[^"\\]|\\.)*"|\S+)/g;

function _unquote(value) {
    if (value.length >= 2 && value.charAt(0) === "\"" && value.charAt(value.length - 1) === "\"")
        return value.slice(1, -1).replace(/\\(.)/g, "$1");
    return value;
}

// One send/recv stderr line to { level, msg, fields }, or null for a line
// that carries no `level=` at all (a stray warning from a dependency, a
// blank line). `fields` is every key=value pair on the line including
// `level`/`msg` themselves, so a caller after `file`/`error`/`remote`/
// `session` (whichever the event actually carries) just reads it off there.
function parseSlogLine(line) {
    var text = String(line || "");
    if (!/\blevel=\w+\b/.test(text))
        return null;
    var fields = {};
    var re = new RegExp(_KV_RE.source, "g");
    var kv;
    while ((kv = re.exec(text)) !== null)
        fields[kv[1]] = _unquote(kv[2]);
    return {
        level: fields.level || "",
        msg: fields.msg || "",
        fields: fields
    };
}

// --- send outcome --------------------------------------------------------

// `send`'s own exit code is 0 even when a file failed (only sender.Start()'s
// top-level error is fatal, everything inside the per-file loop is a
// slog.Error that the loop swallows and moves on from -- cmd/send/send.go),
// so the real outcome is read off stderr's ERROR lines, not the exit code
// alone. `fatal` is the one case exit code still means something: the top-
// level error, which never even reaches the per-file loop.
function sendOutcome(exitCode, stderrText) {
    var lines = String(stderrText || "").split("\n");
    var failed = [];
    for (var i = 0; i < lines.length; i++) {
        var e = parseSlogLine(lines[i]);
        if (e === null || e.level !== "ERROR")
            continue;
        failed.push({
            msg: e.msg,
            file: e.fields.file || e.fields.dir || "",
            error: e.fields.error || ""
        });
    }
    return {
        ok: exitCode === 0 && failed.length === 0,
        fatal: exitCode !== 0,
        failed: failed
    };
}

// --- recv lines ----------------------------------------------------------

// `recv` logs an accept ("Accepting file", before the PIN/no-prompt path in
// preUploadHandler ever gets to the upload itself) but never a per-file
// "saved" line, so this is read for the in-flight indicator only; the toast
// on an actual arrival comes from LocalsendService's own directory watch,
// the one place a save is ever observable.
function parseRecvLine(line) {
    var e = parseSlogLine(line);
    if (e === null)
        return null;
    if (e.level === "ERROR")
        return { type: "error", message: e.msg + (e.fields.error ? ": " + e.fields.error : "") };
    if (e.msg === "Accepting file")
        return { type: "accepting", remote: e.fields.remote || "", session: e.fields.session || "" };
    return { type: "other" };
}

// --- directory watch -------------------------------------------------------

// `current` against `prev` (both plain filename arrays, one `find -maxdepth
// 1 -type f -printf '%f\n'` snapshot each), newest-appearance order not
// tracked since a listing carries none: the caller announces them in
// whatever order the snapshot did.
function newFiles(prevNames, currentNames) {
    var prev = {};
    (prevNames || []).forEach(function (n) { prev[n] = true; });
    return (currentNames || []).filter(function (n) { return !prev[n]; });
}

.pragma library

// Pure math + parsing for the network speed test (M16 Task 9, "flat ledger
// rows, no gauges": omarchy's feature ported, its arc-gauge chrome
// deliberately left behind). NetworkPanel.qml drives real `ip route get`/
// `cat /sys/class/net/.../statistics/*`/`curl` Processes and feeds their
// output through these helpers; nothing here touches Qt.

// bytesDelta/msDelta -> Mbps. A non-positive duration (two samples with the
// same timestamp) and a non-positive delta (a counter reset, e.g. the
// interface flapped mid-run, or rx/tx wrapped) both read as 0 rather than
// an infinite or negative rate, matching omarchy's own
// `if (after < before) print 0` guard.
function mbps(bytesDelta, msDelta) {
    if (!(msDelta > 0) || !(bytesDelta > 0))
        return 0;
    return (bytesDelta * 8) / msDelta / 1000;
}

// omarchy's format_mbps: sub-10 Mbps keeps one decimal (the range where a
// whole number would hide a real difference), 10 and above rounds off.
function formatMbps(value) {
    if (!(value > 0))
        return "0.0";
    if (value < 10)
        return value.toFixed(1);
    return Math.round(value).toString();
}

// Flat ledger fill fraction: current/expected-max, capped at 1 so a link
// faster than the nominal scale never overruns the track. No gauge
// rescaling, no needle sweep: the fraction just clamps.
var DEFAULT_MAX_MBPS = 1000;

function fillFraction(value, maxMbps) {
    maxMbps = maxMbps > 0 ? maxMbps : DEFAULT_MAX_MBPS;
    if (!(value > 0))
        return 0;
    return Math.max(0, Math.min(1, value / maxMbps));
}

// Sample-window reducer: each call folds one (t, bytes) reading (a
// millisecond timestamp paired with a cumulative rx_bytes/tx_bytes counter)
// into a running window covering one phase (download or upload).
// `liveMbps` is the instantaneous rate since the PREVIOUS sample (what a
// live ledger row shows while the phase is in flight); `avgMbps` is the
// rate across the WHOLE window since the phase began (what settles as the
// final result once the phase's bounded duration ends). Averaging over
// the full run, rather than trusting the last tick, smooths over one
// unusually slow or fast sample.
function initWindow() {
    return { first: null, prev: null, liveMbps: 0, avgMbps: 0 };
}

function addSample(state, t, bytes) {
    if (!state.first)
        return { first: { t: t, bytes: bytes }, prev: { t: t, bytes: bytes }, liveMbps: 0, avgMbps: 0 };
    return {
        first: state.first,
        prev: { t: t, bytes: bytes },
        liveMbps: mbps(bytes - state.prev.bytes, t - state.prev.t),
        avgMbps: mbps(bytes - state.first.bytes, t - state.first.t)
    };
}

// "192.0.2.1 via 10.0.2.2 dev eth0 src 10.0.2.15 uid 0" -> "eth0", scanning
// every field for the literal "dev" token the same way omarchy's own awk
// does. Honest null when `ip` printed nothing (missing binary, no route at
// all) or the output has no "dev <iface>" pair.
function parseIface(routeOutput) {
    var match = /\bdev\s+(\S+)/.exec(routeOutput || "");
    return match ? match[1] : null;
}

// Two-line `cat rx_bytes tx_bytes` stdout -> {rx, tx}. Honest null on
// anything short of two parseable non-negative integers: a missing/
// unreadable statistics file leaves `cat`'s stdout short a line (it prints
// an error to stderr for that argument and moves on to the next), and an
// interface that disappears mid-read can leave the file empty.
function parseStatBytes(text) {
    var lines = (text || "").split("\n").map(function (l) { return l.trim(); }).filter(function (l) { return l !== ""; });
    if (lines.length < 2)
        return null;
    var rx = parseInt(lines[0], 10);
    var tx = parseInt(lines[1], 10);
    if (!isFinite(rx) || !isFinite(tx) || rx < 0 || tx < 0)
        return null;
    return { rx: rx, tx: tx };
}

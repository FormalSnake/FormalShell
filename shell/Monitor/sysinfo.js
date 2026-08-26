.pragma library

// Pure parsers for the M38 system monitor: each function takes one
// Monitor/collect.js section's text and returns a plain value, no
// Quickshell/Process/FileView access, so every shape here is testable head
// on against bytes captured from real hardware (tests/tst_monitor_sysinfo.qml,
// same split as Usage/usage.js and Display/outputs.js).
//
// Every fraction this module returns is 0..1, never 0..100: the repo-wide
// convention (CLAUDE.md), already the source of two shipped bugs when a
// caller assumed otherwise. A missing or empty section is an empty array or
// an `{available:false}` object, never a throw: the collector runs on
// machines with no hwmon, no /proc/net interfaces beyond loopback, or a
// swapless VM, and all of that is a normal state to render, not an error.
//
// Delta functions (`cpuDelta`, `netDelta`) need two samples to mean
// anything. Called with no previous sample they return `null`, never a
// fabricated 0, which would read as "measured zero load" instead of "no
// measurement yet".

function _lines(text) {
    if (typeof text !== "string" || text === "")
        return [];
    return text.split("\n").filter(function (line) { return line.length > 0; });
}

// ---- /proc/stat ---------------------------------------------------------

// One record per `cpu`/`cpuN` line: named jiffie counters plus the two
// derived totals `cpuDelta` needs. `total` follows the common
// user+nice+system+idle+iowait+irq+softirq+steal formula (guest/guest_nice
// are already folded into user/nice by the kernel, so adding them again
// would double-count); `idleAll` is idle+iowait.
function parseStat(text) {
    var records = [];
    var lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
        var m = /^(cpu\d*)\s+(.*)$/.exec(lines[i]);
        if (!m)
            continue;
        var fields = m[2].trim().split(/\s+/).map(Number);
        if (fields.length < 4)
            continue;

        var user = fields[0] || 0, nice = fields[1] || 0, system = fields[2] || 0, idle = fields[3] || 0;
        var iowait = fields[4] || 0, irq = fields[5] || 0, softirq = fields[6] || 0, steal = fields[7] || 0;
        var guest = fields[8] || 0, guestNice = fields[9] || 0;
        var idleAll = idle + iowait;

        records.push({
            label: m[1],
            user: user, nice: nice, system: system, idle: idle,
            iowait: iowait, irq: irq, softirq: softirq, steal: steal,
            guest: guest, guestNice: guestNice,
            idleAll: idleAll,
            total: user + nice + system + idle + iowait + irq + softirq + steal
        });
    }
    return records;
}

function _statByLabel(records) {
    var map = {};
    for (var i = 0; i < records.length; i++)
        map[records[i].label] = records[i];
    return map;
}

// A total delta of zero or less (no time elapsed, or a counter reset) has
// nothing to divide by, so it means "unusable" rather than "0% busy".
function _busyFraction(prevRecord, nextRecord) {
    var totalDelta = nextRecord.total - prevRecord.total;
    if (!isFinite(totalDelta) || totalDelta <= 0)
        return null;
    var busyDelta = totalDelta - (nextRecord.idleAll - prevRecord.idleAll);
    return Math.max(0, Math.min(1, busyDelta / totalDelta));
}

// Aggregate + per-core busy fractions between two parseStat() samples.
// Cores keep `next`'s own line order (cpu0, cpu1, ...) rather than an
// object's iteration order, which nothing here guarantees. A core present
// in `next` but not `prev` (hot-plugged since the last tick) is left out of
// `cores` instead of reporting a fabricated fraction for it.
function cpuDelta(prev, next) {
    if (!prev || !next || prev.length === 0 || next.length === 0)
        return null;

    var prevByLabel = _statByLabel(prev);
    var aggPrev = prevByLabel["cpu"];
    var aggNext = null;
    for (var i = 0; i < next.length; i++) {
        if (next[i].label === "cpu") {
            aggNext = next[i];
            break;
        }
    }
    if (!aggPrev || !aggNext)
        return null;

    var aggregate = _busyFraction(aggPrev, aggNext);
    if (aggregate === null)
        return null;

    var cores = [];
    for (var j = 0; j < next.length; j++) {
        var rec = next[j];
        if (rec.label === "cpu")
            continue;
        var prevRec = prevByLabel[rec.label];
        if (!prevRec)
            continue;
        var fraction = _busyFraction(prevRec, rec);
        if (fraction !== null)
            cores.push({ label: rec.label, fraction: fraction });
    }

    return { aggregate: aggregate, cores: cores };
}

// ---- /proc/meminfo --------------------------------------------------------

// Bytes throughout (the section carries kB), plus a used fraction derived
// from MemAvailable, the kernel's own estimate of reclaimable memory,
// closer to "what a user would call used" than MemTotal-MemFree.
function parseMem(text) {
    var lines = _lines(text);
    var kb = {};
    for (var i = 0; i < lines.length; i++) {
        var m = /^(\w+):\s+(\d+)\s*kB$/.exec(lines[i]);
        if (m)
            kb[m[1]] = Number(m[2]);
    }
    if (kb.MemTotal === undefined)
        return { available: false };

    var totalBytes = kb.MemTotal * 1024;
    var availableBytes = (kb.MemAvailable !== undefined ? kb.MemAvailable : (kb.MemFree || 0)) * 1024;
    var freeBytes = (kb.MemFree || 0) * 1024;
    var swapTotalBytes = (kb.SwapTotal || 0) * 1024;
    var swapFreeBytes = (kb.SwapFree || 0) * 1024;

    return {
        available: true,
        totalBytes: totalBytes,
        availableBytes: availableBytes,
        freeBytes: freeBytes,
        swapTotalBytes: swapTotalBytes,
        swapFreeBytes: swapFreeBytes,
        usedFraction: totalBytes > 0 ? Math.max(0, Math.min(1, (totalBytes - availableBytes) / totalBytes)) : 0
    };
}

// ---- /proc/loadavg --------------------------------------------------------

function parseLoad(text) {
    var line = _lines(text)[0];
    if (!line)
        return { available: false };
    var m = /^([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\/(\d+)\s+(\d+)/.exec(line.trim());
    if (!m)
        return { available: false };
    return {
        available: true,
        load1: Number(m[1]),
        load5: Number(m[2]),
        load15: Number(m[3]),
        runningProcs: Number(m[4]),
        totalProcs: Number(m[5]),
        lastPid: Number(m[6])
    };
}

// ---- /proc/uptime ----------------------------------------------------------

function parseUptime(text) {
    var line = _lines(text)[0];
    if (!line)
        return { available: false };
    var parts = line.trim().split(/\s+/);
    if (parts.length < 2)
        return { available: false };
    var uptimeSeconds = Number(parts[0]);
    var idleSeconds = Number(parts[1]);
    if (!isFinite(uptimeSeconds) || !isFinite(idleSeconds))
        return { available: false };
    return { available: true, uptimeSeconds: uptimeSeconds, idleSeconds: idleSeconds };
}

// ---- /proc/net/dev ---------------------------------------------------------

// One row per interface, `lo` excluded: loopback traffic is never what a
// system monitor's network row means. Row shape is deliberately minimal
// (rx/tx byte counters); everything else /proc/net/dev carries is dropped
// at the parse boundary rather than threaded through unused.
function parseNet(text) {
    var lines = _lines(text);
    var rows = [];
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var colon = line.indexOf(":");
        if (colon < 0)
            continue;
        var iface = line.slice(0, colon).trim();
        if (iface === "" || iface === "lo")
            continue;
        var fields = line.slice(colon + 1).trim().split(/\s+/).map(Number);
        if (fields.length < 9)
            continue;
        rows.push({ iface: iface, rxBytes: fields[0] || 0, txBytes: fields[8] || 0 });
    }
    return rows;
}

// bytes/sec per interface between two parseNet() samples, matched by
// interface name. An interface missing from `prev` (came up since the last
// tick) or whose counters went backwards (reset) is left out of the result
// rather than reporting a rate that was never actually measured.
function netDelta(prev, next, elapsedMs) {
    if (!prev || !next || !isFinite(elapsedMs) || elapsedMs <= 0)
        return null;

    var prevByIface = {};
    for (var i = 0; i < prev.length; i++)
        prevByIface[prev[i].iface] = prev[i];

    var seconds = elapsedMs / 1000;
    var rows = [];
    for (var j = 0; j < next.length; j++) {
        var n = next[j];
        var p = prevByIface[n.iface];
        if (!p)
            continue;
        var rxDelta = n.rxBytes - p.rxBytes;
        var txDelta = n.txBytes - p.txBytes;
        if (rxDelta < 0 || txDelta < 0)
            continue;
        rows.push({ iface: n.iface, rxBytesPerSec: rxDelta / seconds, txBytesPerSec: txDelta / seconds });
    }
    return rows;
}

// ---- hwmon temperatures -----------------------------------------------

// One row per `chip|file|label|millidegrees` collector line. `label` falls
// back to the chip name when the kernel exposes no *_label file for that
// sensor (iwlwifi's radio sensor, most acpitz zones); the chip name is
// kept on the row either way so the UI can group sensors that share it.
function parseTemps(text) {
    var rows = [];
    var lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
        var fields = lines[i].split("|");
        if (fields.length < 4)
            continue;
        var chip = fields[0];
        var milli = Number(fields[3]);
        if (!isFinite(milli))
            continue;
        rows.push({
            chip: chip,
            id: fields[1],
            label: fields[2] !== "" ? fields[2] : chip,
            celsius: milli / 1000
        });
    }
    return rows;
}

// ---- hwmon fans -------------------------------------------------------

// One row per `chip|file|label|rpm` collector line, the same four-field
// shape parseTemps reads. `label` falls back to the chip name when the
// kernel exposes no *_label file for that tachometer (acpi_fan's single
// unnamed one; the asus chip labels its own cpu_fan/gpu_fan).
//
// A reading of 0 is a row, not a dropped one: a fan the firmware has
// spun down is a fact about the machine, and hiding it would make a
// stopped fan and an absent one look the same.
function parseFans(text) {
    var rows = [];
    var lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
        var fields = lines[i].split("|");
        if (fields.length < 4)
            continue;
        var chip = fields[0];
        // Number("") is 0, so an empty reading has to be rejected before
        // the isFinite check or an unreadable tachometer would render as a
        // stopped one.
        if (fields[3].trim() === "")
            continue;
        var rpm = Number(fields[3]);
        if (!isFinite(rpm))
            continue;
        rows.push({
            chip: chip,
            id: fields[1],
            label: fields[2] !== "" ? fields[2] : chip,
            rpm: rpm
        });
    }
    return rows;
}

// ---- disk usage -------------------------------------------------------

// `df --output=source,target,size,used`'s rows, already in bytes (collect.js
// runs `df -B1`). `fraction` is used/size, clamped, 0 for a zero-size
// target.
//
// Deduplicated by `source`: a NixOS machine's overlay/bind mounts put the
// same device under several mount points, and without this a single
// filesystem renders as one row per mount. Identity is the device string,
// never size -- two distinct filesystems can legitimately report the same
// size (9p mounts sharing a host directory's free space do). The row kept
// for a repeated source is the one with the shortest mount path, the one a
// human recognises (`/` over `/nix/store`).
function parseDisk(text) {
    var bySource = {};
    var order = [];
    var lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
        var m = /^(\S+)\s+(.+?)\s+(\d+)\s+(\d+)$/.exec(lines[i].trim());
        if (!m)
            continue;
        var source = m[1];
        var mount = m[2];
        var size = Number(m[3]);
        var used = Number(m[4]);
        var row = {
            source: source,
            mount: mount,
            size: size,
            used: used,
            fraction: size > 0 ? Math.max(0, Math.min(1, used / size)) : 0
        };

        var existing = bySource[source];
        if (!existing) {
            bySource[source] = row;
            order.push(source);
        } else if (mount.length < existing.mount.length) {
            bySource[source] = row;
        }
    }

    var rows = [];
    for (var j = 0; j < order.length; j++)
        rows.push(bySource[order[j]]);
    return rows;
}

.pragma library

// Process-table parsers for the launcher's process route (M39), the same
// pure-function split Monitor/sysinfo.js draws for the fixed /proc files:
// nothing here touches Quickshell, Process or FileView, so every shape is
// testable head on against bytes captured from a real machine
// (tests/tst_monitor_procs.qml, tests/fixtures/procs-vm.txt).
//
// The collector is its own `sh -c` script rather than a section bolted onto
// Monitor/collect.js: a 400-process machine pays for two extra passes over
// /proc per tick, and the bar cell and the compact panel have no process
// list to draw. It runs only while something is subscribed to
// ProcessService, which in practice means only while the process route is
// open.
//
// Two passes, two forks, no per-process fork: `cat /proc/[0-9]*/stat` reads
// every process's stat file in ONE exec, and `grep -a -H ''` does the same
// for the cmdlines, printing each with its own path so the pid survives.
// The `tr` after it turns cmdline's NUL separators into spaces before any
// of it reaches QML, because a NUL inside a QString is a byte nothing
// downstream (split, regex, Text) treats as a separator.
//
// Every fraction below is 0..1 (the repo-wide convention), and CPU is
// measured against the WHOLE machine, not one core: a process pinning one
// core of six reads 0.167 here, where htop would say 100%. That keeps a
// process row directly comparable with the monitor view's own CPU TOTAL
// row, which is machine-wide too.
var COLLECTOR_SCRIPT = [
    'echo "@stat"; grep -E \'^cpu \' /proc/stat',
    'echo "@mem"; grep -E \'^MemTotal:\' /proc/meminfo',
    'echo "@meta"; getconf PAGESIZE',
    'echo "@procs"; cat /proc/[0-9]*/stat 2>/dev/null',
    'echo "@cmdline"; grep -a -H "" /proc/[0-9]*/cmdline 2>/dev/null | tr "\\0" " "',
    'echo "@end"'
].join("\n");

function collectCommand() {
    return ["sh", "-c", COLLECTOR_SCRIPT];
}

function _lines(text) {
    if (typeof text !== "string" || text === "")
        return [];
    return text.split("\n").filter(function (line) { return line.length > 0; });
}

// ---- sections -----------------------------------------------------------

// Total jiffies across all CPUs off the aggregate `cpu` line, which is what
// a per-process delta is measured against. null when the section is missing
// or unparsable, never 0: 0 would divide into a fabricated 100%.
function totalJiffies(text) {
    var lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
        var m = /^cpu\s+(.*)$/.exec(lines[i]);
        if (!m)
            continue;
        var fields = m[1].trim().split(/\s+/).map(Number);
        if (fields.length < 4)
            return null;
        var total = 0;
        // user+nice+system+idle+iowait+irq+softirq+steal, dropping
        // guest/guest_nice for the same reason parseStat does: the kernel
        // has already folded them into user/nice.
        for (var f = 0; f < 8 && f < fields.length; f++)
            total += fields[f] || 0;
        return total;
    }
    return null;
}

function memTotalBytes(text) {
    var m = /MemTotal:\s+(\d+)\s*kB/.exec(typeof text === "string" ? text : "");
    return m ? Number(m[1]) * 1024 : null;
}

// getconf PAGESIZE, because RSS in /proc/PID/stat is counted in pages and
// aarch64 kernels are free to use 16K ones. A missing or absurd answer
// falls back to 4096 rather than reporting every process at 0 bytes.
function pageSize(text) {
    var value = Number((typeof text === "string" ? text : "").trim());
    return (isFinite(value) && value >= 1024) ? value : 4096;
}

// ---- /proc/PID/stat -----------------------------------------------------

// comm sits in parens as field 2 and may itself contain spaces AND parens
// ("(sd-pam)", a process that prctl'd its name), so it is cut between the
// FIRST "(" and the LAST ")" rather than split on whitespace. Field offsets
// after that are counted from state (index 0 below = stat field 3).
function parseProcs(text) {
    var records = [];
    var lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var open = line.indexOf("(");
        var close = line.lastIndexOf(")");
        if (open < 1 || close < open)
            continue;
        var pid = Number(line.slice(0, open).trim());
        if (!isFinite(pid) || pid <= 0)
            continue;
        var rest = line.slice(close + 1).trim().split(/\s+/);
        if (rest.length < 22)
            continue;
        var utime = Number(rest[11]) || 0;
        var stime = Number(rest[12]) || 0;
        records.push({
            pid: pid,
            name: line.slice(open + 1, close),
            state: rest[0],
            ppid: Number(rest[1]) || 0,
            jiffies: utime + stime,
            threads: Number(rest[17]) || 0,
            // Boot-relative, so it never changes for a live process: the one
            // field that tells a recycled pid apart from the same process
            // still running (see procDelta).
            startedAt: Number(rest[19]) || 0,
            rssPages: Number(rest[21]) || 0
        });
    }
    return records;
}

// `grep -a -H '' /proc/[0-9]*/cmdline` rows, one per process that has one.
// A kernel thread's cmdline is genuinely empty, so it produces no row at
// all and the pid is simply absent from the map.
function parseCmdlines(text) {
    var map = {};
    var lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
        var m = /^\/proc\/(\d+)\/cmdline:(.*)$/.exec(lines[i]);
        if (!m)
            continue;
        var cmd = m[2].replace(/\s+$/, "");
        if (cmd !== "")
            map[m[1]] = cmd;
    }
    return map;
}

// ---- rows ---------------------------------------------------------------

// prev/next are parseProcs outputs, `totalDelta` the jiffie delta between
// the two samples. Returns one display row per process in `next`.
//
// cpuFraction is null (a dash on screen, never a 0%) for the first sample
// after a subscribe, for a process this poll saw for the first time, and
// for a pid whose startedAt moved, which means the number was recycled onto
// a different process between ticks and the old counter is not comparable.
function procDelta(prev, next, totalDelta, opts) {
    var options = opts || {};
    var bytesPerPage = options.pageSize || 4096;
    var memTotal = options.memTotalBytes || null;
    var byPid = {};
    var i;
    for (i = 0; prev && i < prev.length; i++)
        byPid[prev[i].pid] = prev[i];

    var usable = typeof totalDelta === "number" && totalDelta > 0;
    var rows = [];
    for (i = 0; i < (next || []).length; i++) {
        var rec = next[i];
        var was = byPid[rec.pid];
        var fraction = null;
        if (usable && was && was.startedAt === rec.startedAt) {
            var busy = rec.jiffies - was.jiffies;
            if (busy < 0)
                busy = 0;
            fraction = Math.min(1, busy / totalDelta);
        }
        var bytes = rec.rssPages * bytesPerPage;
        var cmd = (options.cmdlines || {})[String(rec.pid)] || "";
        rows.push({
            pid: rec.pid,
            ppid: rec.ppid,
            name: rec.name,
            // A kernel thread has no argv to show, which is a fact about the
            // process rather than a gap in the reading, so it renders in the
            // brackets ps uses for exactly this.
            cmd: cmd,
            kernel: cmd === "",
            state: rec.state,
            threads: rec.threads,
            cpuFraction: fraction,
            memBytes: bytes,
            memFraction: memTotal ? Math.min(1, bytes / memTotal) : null
        });
    }
    return rows;
}

// ---- filter and sort ----------------------------------------------------

// Case-insensitive substring over the name and the argv, plus an exact pid
// match so a pid pasted in from a log finds its row. Matching the argv is
// what makes "python" find a script the kernel named after its interpreter
// and "electron" find every app built on one, which comm alone (15 bytes,
// truncated by the kernel) cannot do.
function filterRows(rows, query) {
    var q = (typeof query === "string" ? query : "").trim().toLowerCase();
    if (q === "")
        return (rows || []).slice();
    var out = [];
    for (var i = 0; i < (rows || []).length; i++) {
        var row = rows[i];
        if (String(row.pid) === q
            || row.name.toLowerCase().indexOf(q) >= 0
            || row.cmd.toLowerCase().indexOf(q) >= 0)
            out.push(row);
    }
    return out;
}

var SORTS = ["cpu", "mem", "pid", "name"];

// Every mode breaks its own ties on pid, so the order two idle processes
// sit in cannot flip between polls: a list that reshuffled under the cursor
// every two seconds would make the cursor point at a different process than
// the one the reader aimed at. A null cpuFraction (nothing measured yet)
// sorts as the bottom of the CPU column rather than as zero.
function sortRows(rows, mode) {
    var key = SORTS.indexOf(mode) >= 0 ? mode : "cpu";
    var out = (rows || []).slice();
    out.sort(function (a, b) {
        var d = 0;
        if (key === "cpu")
            d = (b.cpuFraction === null ? -1 : b.cpuFraction) - (a.cpuFraction === null ? -1 : a.cpuFraction);
        else if (key === "mem")
            d = b.memBytes - a.memBytes;
        else if (key === "name")
            d = a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0);
        if (d !== 0)
            return d;
        return a.pid - b.pid;
    });
    return out;
}

function nextSort(mode) {
    var i = SORTS.indexOf(mode);
    return SORTS[(i < 0 ? 0 : i + 1) % SORTS.length];
}

// ---- actions ------------------------------------------------------------

// The signals a process row can send. TERM asks, KILL takes, HUP is what a
// daemon reloads on, and INT is what Ctrl-C would have sent had the process
// been in a terminal. Anything outside this list is refused by name rather
// than passed through to `kill`, so an IPC caller cannot reach for a signal
// this surface never meant to offer.
var SIGNALS = ["TERM", "KILL", "HUP", "INT"];

function isValidPid(pid) {
    var n = Number(pid);
    return isFinite(n) && n > 0 && Math.floor(n) === n;
}

function normalizeSignal(name) {
    var s = String(name === undefined || name === null ? "" : name).trim().toUpperCase();
    if (s === "")
        return "TERM";
    if (s.indexOf("SIG") === 0)
        s = s.slice(3);
    return SIGNALS.indexOf(s) >= 0 ? s : "";
}

// `kill` as the shell builtin, not the procps binary: every POSIX sh has
// it, and this shell ships no dependency on procps anywhere else. The pid
// is interpolated only after isValidPid, so it is always digits.
function killCommand(pid, signal) {
    return ["sh", "-c", "kill -s " + signal + " " + String(Number(pid))];
}

// The exact argv, one arg per line: the poll's own cmdline pass replaced
// NULs with spaces for display, which loses the boundary between an
// argument and a space inside one. A restart has to re-exec the real thing,
// so it re-reads the file with the separator intact.
function argvCommand(pid) {
    return ["sh", "-c", "tr '\\0' '\\n' < /proc/" + String(Number(pid)) + "/cmdline"];
}

// Empty for a process that died between the read and the parse (an empty
// cmdline is also what a kernel thread has, which is why nothing offers a
// restart on one).
function parseArgv(text) {
    return _lines(text);
}

function aliveCommand(pid) {
    return ["sh", "-c", "test -d /proc/" + String(Number(pid))];
}

function _shq(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

// Re-runs the argv from the process's own working directory. `exec` so the
// wrapping shell is replaced rather than left sitting around as the parent,
// and `cd` only when a cwd was actually readable: /proc/PID/cwd is a
// symlink only the owner (or root) may follow, so another user's process
// restarts from the shell's own cwd instead of failing outright.
//
// This restores the command line, never the environment: a process launched
// with variables its parent set (a dev server, an offloaded GPU launch)
// comes back without them. That is the honest limit of restarting something
// by pid, and the reason the reply says "re-ran" rather than "restored".
function respawnCommand(argv, cwd) {
    var line = (argv || []).map(_shq).join(" ");
    if (cwd)
        return ["sh", "-c", "cd " + _shq(cwd) + " && exec " + line];
    return ["sh", "-c", "exec " + line];
}

function cwdCommand(pid) {
    return ["sh", "-c", "readlink /proc/" + String(Number(pid)) + "/cwd 2>/dev/null || true"];
}

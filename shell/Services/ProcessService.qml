pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Compositor
import qs.Core as Core
import "../Monitor/collect.js" as Collect
import "../Monitor/procs.js" as Procs

// The live process table, and the three things a row can do to a process
// (M39). Same shape as SystemMonitorService: one `sh -c` collector per poll
// tick parsed through pure functions in Monitor/procs.js, subscribe() /
// unsubscribe() ref-counting who wants it, and no timer at all while the
// count is zero.
//
// A separate service rather than two more sections on SystemMonitorService's
// own collector, because the two have different audiences: the bar cell and
// the compact panel want CPU and memory every two seconds and have no
// process list to draw, while the process route wants a full /proc walk and
// only exists while it is on screen. Folding them together would make every
// shell with the monitor cell enabled walk 400 processes forever.
//
// `rows` is unsorted and unfiltered: ordering and matching are the view's
// call (Procs.sortRows / Procs.filterRows), because two consumers of the
// same tick can reasonably want different orders and the sort is cheap
// enough to redo per consumer.
//
// Actions are deliberately blunt and few: a signal (TERM/KILL/HUP/INT) and
// a restart, which is a TERM followed by re-running the same argv once the
// process is actually gone. Nothing here renices, changes affinity, or
// touches a cgroup: those need policy this shell has no way to ask about.
Singleton {
    id: root

    property var rows: []
    property bool available: false
    property real lastTickAt: 0

    // The last action's outcome, in the shape the view's status line and
    // MonitorIpc both read: { pid, action, ok, message, at }. Null until
    // something has been acted on this session.
    property var lastResult: null
    signal actionFinished(var result)

    property int _subscribers: 0
    property var _prevProcs: null
    property real _prevTotal: 0

    function subscribe() {
        root._subscribers++;
        if (root._subscribers === 1)
            root._runTick();
    }

    function unsubscribe() {
        root._subscribers = Math.max(0, root._subscribers - 1);
    }

    readonly property int _interval: {
        var v = Core.Config.get("monitor.processIntervalMs", 2000);
        if (typeof v !== "number" || !isFinite(v))
            v = 2000;
        return Math.max(500, Math.round(v));
    }

    function rowByPid(pid) {
        for (var i = 0; i < root.rows.length; i++) {
            if (root.rows[i].pid === Number(pid))
                return root.rows[i];
        }
        return null;
    }

    Timer {
        interval: root._interval
        running: root._subscribers > 0
        repeat: true
        onTriggered: root._runTick()
    }

    // Skips rather than queues while the previous walk is still in flight,
    // exactly as SystemMonitorService does: a machine slow enough to still
    // be reading /proc degrades to a slower poll instead of running two
    // collectors over the same files.
    function _runTick() {
        if (proc.running)
            return;
        proc.command = Procs.collectCommand();
        proc.running = true;
    }

    function _applyBlob(blob) {
        // splitSections is Monitor/collect.js's, reused verbatim: the marker
        // format is the same, so the process collector needs no splitter of
        // its own.
        var sections = Collect.splitSections(blob);
        var records = Procs.parseProcs(sections.procs);
        var total = Procs.totalJiffies(sections.stat);
        var delta = (total !== null && root._prevTotal > 0) ? (total - root._prevTotal) : 0;

        root.rows = Procs.procDelta(root._prevProcs, records, delta, {
            pageSize: Procs.pageSize(sections.meta),
            memTotalBytes: Procs.memTotalBytes(sections.mem),
            cmdlines: Procs.parseCmdlines(sections.cmdline)
        });
        root.available = records.length > 0;
        root._prevProcs = records;
        root._prevTotal = total === null ? 0 : total;
        root.lastTickAt = Date.now();
    }

    Process {
        id: proc
        stdout: StdioCollector { id: collector }
        onExited: exitCode => root._applyBlob(collector.text)
    }

    // ---- actions --------------------------------------------------------

    function _finish(pid, action, ok, message) {
        var result = { pid: Number(pid), action: action, ok: ok, message: message, at: Date.now() };
        root.lastResult = result;
        root.actionFinished(result);
        // The table is one poll behind an action that worked, and a row for
        // a process that is already gone invites a second Enter on it, so
        // the successful case re-reads /proc now instead of at the next
        // tick.
        if (ok && root._subscribers > 0)
            root._runTick();
        return result;
    }

    // Returns the reply string synchronously (the IPC contract's shape); the
    // signal's own exit status lands in lastResult a moment later, since a
    // Process cannot be waited on from here.
    function signalPid(pid, signalName) {
        if (!Procs.isValidPid(pid))
            return "error: '" + pid + "' is not a pid";
        var sig = Procs.normalizeSignal(signalName);
        if (sig === "")
            return "error: signal must be one of " + Procs.SIGNALS.join(", ");
        if (killProc.running)
            return "error: a signal is already in flight";
        killProc.pid = Number(pid);
        killProc.signalName = sig;
        killProc.command = Procs.killCommand(pid, sig);
        killProc.running = true;
        return "ok: " + sig + " sent to " + Number(pid);
    }

    Process {
        id: killProc
        property int pid: 0
        property string signalName: ""
        stderr: StdioCollector { id: killErr }
        onExited: exitCode => {
            if (exitCode === 0)
                root._finish(killProc.pid, killProc.signalName, true, "sent");
            else
                root._finish(killProc.pid, killProc.signalName, false,
                    (killErr.text || "kill exited " + exitCode).trim());
        }
    }

    // ---- restart --------------------------------------------------------
    //
    // Four steps, each one a Process, because every one of them can fail in
    // a way the next step must not paper over: read the exact argv, read the
    // cwd, TERM it, then wait for the pid to actually leave /proc before
    // re-running anything. Spawning while the old process is still up would
    // give the user two copies of it, which is the one outcome worse than a
    // restart that did not happen.
    //
    // The wait is bounded (_restartTimeoutMs). A process that ignores TERM
    // is reported as still running rather than escalated to KILL on its
    // own: escalating without being asked is how a restart turns into data
    // loss in an editor with unsaved buffers.
    readonly property int _restartTimeoutMs: 5000
    property var _restart: null

    function restartPid(pid) {
        if (!Procs.isValidPid(pid))
            return "error: '" + pid + "' is not a pid";
        if (root._restart !== null)
            return "error: a restart is already in flight for " + root._restart.pid;
        var row = root.rowByPid(pid);
        if (row && row.kernel)
            return "error: " + Number(pid) + " is a kernel thread, it has no command line to re-run";
        root._restart = { pid: Number(pid), argv: [], cwd: "", waited: 0 };
        argvProc.command = Procs.argvCommand(pid);
        argvProc.running = true;
        return "ok: restarting " + Number(pid);
    }

    function _restartFailed(message) {
        var pid = root._restart ? root._restart.pid : 0;
        root._restart = null;
        root._finish(pid, "RESTART", false, message);
    }

    Process {
        id: argvProc
        stdout: StdioCollector { id: argvOut }
        onExited: exitCode => {
            if (!root._restart)
                return;
            var argv = Procs.parseArgv(argvOut.text);
            if (exitCode !== 0 || argv.length === 0) {
                root._restartFailed("no command line to re-run (process gone, or a kernel thread)");
                return;
            }
            root._restart.argv = argv;
            cwdProc.command = Procs.cwdCommand(root._restart.pid);
            cwdProc.running = true;
        }
    }

    Process {
        id: cwdProc
        stdout: StdioCollector { id: cwdOut }
        onExited: exitCode => {
            if (!root._restart)
                return;
            // Unreadable is normal (another user's process), so an empty
            // answer just means the respawn runs from the shell's own cwd.
            root._restart.cwd = (cwdOut.text || "").trim();
            termProc.command = Procs.killCommand(root._restart.pid, "TERM");
            termProc.running = true;
        }
    }

    Process {
        id: termProc
        stderr: StdioCollector { id: termErr }
        onExited: exitCode => {
            if (!root._restart)
                return;
            if (exitCode !== 0) {
                root._restartFailed((termErr.text || "kill exited " + exitCode).trim());
                return;
            }
            waitTimer.restart();
        }
    }

    Timer {
        id: waitTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (!root._restart || aliveProc.running)
                return;
            aliveProc.command = Procs.aliveCommand(root._restart.pid);
            aliveProc.running = true;
        }
    }

    Process {
        id: aliveProc
        onExited: exitCode => {
            if (!root._restart)
                return;
            if (exitCode !== 0) {
                var argv = root._restart.argv;
                var cwd = root._restart.cwd;
                var pid = root._restart.pid;
                root._restart = null;
                // Through the compositor rather than a bare Process, so the
                // child outlives this shell's own process tree exactly as a
                // launcher-started app does.
                CompositorService.spawn(Procs.respawnCommand(argv, cwd));
                root._finish(pid, "RESTART", true, "re-ran " + argv[0]);
                return;
            }
            root._restart.waited += waitTimer.interval;
            if (root._restart.waited >= root._restartTimeoutMs) {
                root._restartFailed("still running " + Math.round(root._restartTimeoutMs / 1000) + "s after TERM, nothing re-run");
                return;
            }
            waitTimer.restart();
        }
    }
}

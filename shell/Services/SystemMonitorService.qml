pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core
import "../Monitor/collect.js" as Collect
import "../Monitor/sysinfo.js" as Sysinfo

// System monitor data layer (M38 Task 4, plan decision D2): one `sh -c`
// collector Process per poll tick, parsed once through Monitor/sysinfo.js's
// pure functions and published as plain properties. No FileView here:
// /proc and /sys/class/hwmon need globbing and defeat FileView's change
// watching (Monitor/collect.js's own header), so this is a Process/Timer
// service in CommandModule.qml's shape, not the FileView-watch idiom most
// of this directory otherwise follows.
//
// subscribe()/unsubscribe() ref-count who currently wants live data (the
// bar cell while visible, the compact panel and the launcher's full view
// while open, the same acquire()/release() shape DualsenseService and
// AirpodsService use, named subscribe/unsubscribe here since one tick fans
// out to more than one consumer at once, including GpuService). The poll
// timer runs only while the count is above zero, so a shell with the
// monitor cell off and every monitor surface closed spawns nothing at all.
// GpuService rides this same tick instead of running its own collector:
// see its own header for why.
//
// Every delta needs two samples: the first tick after a subscribe from
// zero has no previous /proc/stat or /proc/net/dev sample, so
// cpu.aggregate/cores and net.rows come back null/empty rather than a
// fabricated zero (Monitor/sysinfo.js's own cpuDelta/netDelta contract);
// the second tick fills them in.
Singleton {
    id: root

    property var cpu: ({ available: false, aggregate: null, cores: [] })
    property var mem: ({ available: false })
    property var load: ({ available: false })
    property var uptime: ({ available: false })
    property var temps: ({ available: false, rows: [] })
    property var net: ({ available: false, rows: [] })
    property var disk: ({ available: false, rows: [] })

    // Date.now() of the last completed tick, 0 before the first one lands.
    // MonitorIpc's status()/gpu() report this alongside every reply so a
    // caller can see how stale the sample is instead of trusting it blind.
    property real lastTickAt: 0

    // Fired once per completed collector run, carrying the raw split
    // sections (Monitor/collect.js's splitSections output) so GpuService
    // can read @drm/@nvidia/@gfx without spawning a second Process: the
    // whole point of collecting everything in one `sh -c` script (D2).
    signal tick(var sections)

    property int _subscribers: 0
    property var _prevStat: null
    property var _prevNet: null
    property real _prevNetAt: 0

    function subscribe() {
        root._subscribers++;
        if (root._subscribers === 1)
            root._runTick();
    }

    function unsubscribe() {
        root._subscribers = Math.max(0, root._subscribers - 1);
    }

    readonly property int _interval: {
        var v = Core.Config.get("monitor.intervalMs", 2000);
        if (typeof v !== "number" || !isFinite(v))
            v = 2000;
        return Math.max(500, Math.round(v));
    }

    Timer {
        id: pollTimer
        interval: root._interval
        running: root._subscribers > 0
        repeat: true
        onTriggered: root._runTick()
    }

    // Skips the tick outright when the previous run is still in flight
    // rather than queuing a second one: a slow disk (df on a network
    // mount, a wedged sysfs read) degrades to a slower poll, never two
    // collectors racing over the same output.
    function _runTick() {
        if (proc.running)
            return;
        proc.command = Collect.collectCommand();
        proc.running = true;
    }

    function _applyBlob(blob) {
        root.lastTickAt = Date.now();
        var sections = Collect.splitSections(blob);

        var statRecords = Sysinfo.parseStat(sections.stat);
        var delta = Sysinfo.cpuDelta(root._prevStat, statRecords);
        root.cpu = {
            available: statRecords.length > 0,
            aggregate: delta ? delta.aggregate : null,
            cores: delta ? delta.cores : []
        };
        root._prevStat = statRecords;

        root.mem = Sysinfo.parseMem(sections.mem);
        root.load = Sysinfo.parseLoad(sections.load);
        root.uptime = Sysinfo.parseUptime(sections.uptime);

        var tempRows = Sysinfo.parseTemps(sections.temp);
        root.temps = { available: tempRows.length > 0, rows: tempRows };

        var diskRows = Sysinfo.parseDisk(sections.disk);
        root.disk = { available: diskRows.length > 0, rows: diskRows };

        var now = Date.now();
        var rawNet = Sysinfo.parseNet(sections.net);
        var elapsed = root._prevNetAt > 0 ? now - root._prevNetAt : 0;
        var netRows = Sysinfo.netDelta(root._prevNet, rawNet, elapsed);
        root.net = { available: rawNet.length > 0, rows: netRows || [] };
        root._prevNet = rawNet;
        root._prevNetAt = now;

        root.tick(sections);
    }

    Process {
        id: proc
        stdout: StdioCollector {
            id: collector
        }
        onExited: exitCode => root._applyBlob(collector.text)
    }
}

import QtQuick
import QtTest
import "../shell/Monitor/collect.js" as Collect
import "../shell/Monitor/procs.js" as Procs

// Pure-parser coverage for the M39 process table, the same shape
// tst_monitor_sysinfo.qml draws for the fixed /proc files: two CONSECUTIVE
// real captures of the process collector's own output from the mac VM rig
// (2026-08-19), two seconds apart, with a `sh -c 'while :; do :; done'` busy
// loop running across the gap so there is a real per-process delta to
// measure rather than a table of zeroes.
//
// Both captures are trimmed to the same 23 processes: the whole VM is 141
// of them, and the kept set is what the parsers actually have something to
// say about. It carries the real edge cases from that machine rather than
// invented ones: `((sd-pam))`, whose comm is itself parenthesised;
// `.Hyprland-wrapp` and `power-profiles-`, both cut by the kernel's 15-byte
// comm limit; and kworkers, which have no cmdline at all. The @stat/@mem/
// @meta sections are untouched, so the machine-wide jiffie delta every
// fraction is measured against is the real one.
TestCase {
    name: "MonitorProcs"

    property var a: ({})
    property var b: ({})

    // The busy loop's pid, and the jiffies it burned between the two
    // captures (utime 100 -> 301) against the machine's own 1213-jiffie
    // window: one core of the VM's six.
    readonly property int busyPid: 36642
    readonly property real busyFraction: 201 / 1213

    function _load(path) {
        var done = false;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) done = true;
        };
        xhr.open("GET", Qt.resolvedUrl(path));
        xhr.send();
        tryVerify(function () { return done; }, 5000);
        return xhr.responseText;
    }

    function initTestCase() {
        a = Collect.splitSections(_load("fixtures/procs-vm-a.txt"));
        b = Collect.splitSections(_load("fixtures/procs-vm-b.txt"));
    }

    function _rowFor(rows, pid) {
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].pid === pid)
                return rows[i];
        }
        return null;
    }

    // ---- sections ----

    function test_the_collector_never_takes_an_argument() {
        var cmd = Procs.collectCommand();
        compare(cmd.length, 3);
        compare(cmd[0], "sh");
        compare(cmd[1], "-c");
    }

    function test_split_sections_finds_every_process_marker() {
        var names = ["stat", "mem", "meta", "procs", "cmdline", "end"];
        for (var i = 0; i < names.length; i++)
            verify(a[names[i]] !== undefined, names[i] + " missing");
    }

    function test_total_jiffies_sums_the_aggregate_line_only() {
        compare(Procs.totalJiffies(b.stat) - Procs.totalJiffies(a.stat), 1213);
    }

    // A machine whose /proc/stat never arrived divides into nothing, so the
    // answer is null and every fraction downstream stays unmeasured.
    function test_total_jiffies_is_null_without_a_sample() {
        compare(Procs.totalJiffies(""), null);
    }

    function test_mem_total_is_bytes_not_kilobytes() {
        compare(Procs.memTotalBytes(a.mem), 8098064 * 1024);
    }

    function test_page_size_falls_back_rather_than_reporting_zero_bytes() {
        compare(Procs.pageSize(a.meta), 4096);
        compare(Procs.pageSize(""), 4096);
        compare(Procs.pageSize("garbage"), 4096);
        compare(Procs.pageSize("16384\n"), 16384);
    }

    // ---- /proc/PID/stat ----

    function test_parse_procs_reads_every_row() {
        compare(Procs.parseProcs(a.procs).length, 23);
    }

    function test_parse_procs_cuts_comm_between_the_outer_parens() {
        var rec = _rowFor(Procs.parseProcs(a.procs), 846);
        verify(rec !== null);
        compare(rec.name, "(sd-pam)");
        compare(rec.ppid, 842);
    }

    function test_parse_procs_keeps_the_kernels_truncated_comm_verbatim() {
        var records = Procs.parseProcs(a.procs);
        var names = records.map(function (r) { return r.name; });
        verify(names.indexOf("power-profiles-") >= 0);
    }

    function test_parse_procs_reads_the_counters_the_delta_needs() {
        var rec = _rowFor(Procs.parseProcs(a.procs), busyPid);
        compare(rec.name, "sh");
        compare(rec.jiffies, 100);
        compare(rec.threads, 1);
        compare(rec.rssPages, 886);
        compare(rec.startedAt, 5637636);
    }

    function test_parse_procs_ignores_a_line_it_cannot_place() {
        compare(Procs.parseProcs("garbage\n\n").length, 0);
    }

    // ---- cmdlines ----

    function test_parse_cmdlines_keys_by_pid_from_the_path() {
        var map = Procs.parseCmdlines(a.cmdline);
        compare(map["36642"], "sh -c while :; do :; done");
    }

    // A kworker's cmdline is genuinely empty, so grep prints no row for it
    // and the pid is absent rather than mapped to "".
    function test_parse_cmdlines_has_no_entry_for_a_kernel_thread() {
        var map = Procs.parseCmdlines(a.cmdline);
        compare(map["103"], undefined);
    }

    // ---- procDelta ----

    function _rows() {
        return Procs.procDelta(Procs.parseProcs(a.procs), Procs.parseProcs(b.procs),
            Procs.totalJiffies(b.stat) - Procs.totalJiffies(a.stat), {
                pageSize: Procs.pageSize(b.meta),
                memTotalBytes: Procs.memTotalBytes(b.mem),
                cmdlines: Procs.parseCmdlines(b.cmdline)
            });
    }

    function test_first_sample_measures_nothing_rather_than_zero() {
        var rows = Procs.procDelta(null, Procs.parseProcs(a.procs), 0, {});
        compare(rows.length, 23);
        for (var i = 0; i < rows.length; i++)
            compare(rows[i].cpuFraction, null);
    }

    // One core of six, measured against the whole machine (Monitor/procs.js's
    // own convention, matching the monitor view's machine-wide CPU TOTAL).
    function test_cpu_fraction_is_the_share_of_the_whole_machine() {
        var row = _rowFor(_rows(), busyPid);
        verify(row !== null);
        fuzzyCompare(row.cpuFraction, busyFraction, 0.0001);
    }

    function test_an_idle_process_measures_zero_not_null() {
        var row = _rowFor(_rows(), 1000);
        compare(row.name, "dbus-broker");
        compare(row.cpuFraction, 0);
    }

    // A pid recycled onto a different process between two polls has a
    // counter that is not comparable with the one before it, and the tell is
    // starttime: the row comes back unmeasured rather than carrying a delta
    // taken against a process that no longer exists.
    function test_a_recycled_pid_is_unmeasured_rather_than_wrong() {
        var prev = Procs.parseProcs(a.procs).map(function (rec) {
            return rec.pid === busyPid ? Object.assign({}, rec, { startedAt: rec.startedAt - 1 }) : rec;
        });
        var rows = Procs.procDelta(prev, Procs.parseProcs(b.procs), 1213, {});
        compare(_rowFor(rows, busyPid).cpuFraction, null);
    }

    function test_memory_is_pages_times_the_page_size() {
        var row = _rowFor(_rows(), busyPid);
        compare(row.memBytes, 886 * 4096);
        fuzzyCompare(row.memFraction, (886 * 4096) / (8098064 * 1024), 0.0001);
    }

    function test_a_process_without_an_argv_is_marked_a_kernel_thread() {
        var rows = _rows();
        compare(_rowFor(rows, 103).kernel, true);
        compare(_rowFor(rows, 103).cmd, "");
        compare(_rowFor(rows, busyPid).kernel, false);
    }

    // ---- filter ----

    function test_filter_matches_the_process_name() {
        var rows = Procs.filterRows(_rows(), "kworker");
        verify(rows.length >= 3);
        for (var i = 0; i < rows.length; i++)
            verify(rows[i].name.indexOf("kworker") >= 0);
    }

    // The argv is what a user actually knows a process by: the kernel's comm
    // for the busy loop is "sh", and only its command line says what it is.
    function test_filter_matches_the_command_line_too() {
        var rows = Procs.filterRows(_rows(), "while :;");
        compare(rows.length, 1);
        compare(rows[0].pid, busyPid);
    }

    function test_filter_matches_a_pid_exactly() {
        var rows = Procs.filterRows(_rows(), "1000");
        compare(rows.length, 1);
        compare(rows[0].name, "dbus-broker");
    }

    function test_an_empty_query_is_the_whole_table() {
        compare(Procs.filterRows(_rows(), "").length, 23);
        compare(Procs.filterRows(_rows(), "   ").length, 23);
    }

    function test_filter_is_case_insensitive() {
        compare(Procs.filterRows(_rows(), "DBUS").length, 1);
    }

    // ---- sort ----

    function test_cpu_sort_leads_with_the_busiest_process() {
        var rows = Procs.sortRows(_rows(), "cpu");
        compare(rows[0].pid, busyPid);
    }

    // Two processes measuring the same thing must not trade places between
    // polls, or the cursor lands on a different one than the reader aimed
    // at. Every mode breaks its ties on pid for exactly that reason.
    function test_ties_break_on_pid_so_the_order_cannot_flip() {
        var rows = Procs.sortRows(_rows(), "cpu");
        for (var i = 1; i < rows.length; i++) {
            if (rows[i].cpuFraction === rows[i - 1].cpuFraction)
                verify(rows[i].pid > rows[i - 1].pid);
        }
    }

    function test_unmeasured_cpu_sorts_below_a_measured_zero() {
        var rows = Procs.sortRows([
            { pid: 2, cpuFraction: null, memBytes: 0, name: "b" },
            { pid: 1, cpuFraction: 0, memBytes: 0, name: "a" }
        ], "cpu");
        compare(rows[0].pid, 1);
    }

    function test_mem_sort_is_descending() {
        var rows = Procs.sortRows(_rows(), "mem");
        for (var i = 1; i < rows.length; i++)
            verify(rows[i].memBytes <= rows[i - 1].memBytes);
    }

    function test_pid_sort_is_ascending() {
        var rows = Procs.sortRows(_rows(), "pid");
        for (var i = 1; i < rows.length; i++)
            verify(rows[i].pid > rows[i - 1].pid);
    }

    function test_sort_does_not_reorder_its_input() {
        var rows = _rows();
        var first = rows[0].pid;
        Procs.sortRows(rows, "mem");
        compare(rows[0].pid, first);
    }

    function test_an_unknown_mode_falls_back_to_cpu() {
        compare(Procs.sortRows(_rows(), "nonsense")[0].pid, busyPid);
    }

    function test_next_sort_cycles_the_four_modes() {
        compare(Procs.nextSort("cpu"), "mem");
        compare(Procs.nextSort("mem"), "pid");
        compare(Procs.nextSort("pid"), "name");
        compare(Procs.nextSort("name"), "cpu");
        compare(Procs.nextSort("nonsense"), "cpu");
    }

    // ---- actions ----

    function test_only_the_four_offered_signals_are_accepted() {
        compare(Procs.normalizeSignal("term"), "TERM");
        compare(Procs.normalizeSignal("SIGKILL"), "KILL");
        compare(Procs.normalizeSignal(""), "TERM");
        compare(Procs.normalizeSignal("STOP"), "");
        compare(Procs.normalizeSignal("9"), "");
    }

    function test_a_pid_must_be_a_positive_whole_number() {
        verify(Procs.isValidPid(1));
        verify(Procs.isValidPid("36642"));
        verify(!Procs.isValidPid(0));
        verify(!Procs.isValidPid(-1));
        verify(!Procs.isValidPid(1.5));
        verify(!Procs.isValidPid("1; rm -rf /"));
    }

    function test_kill_interpolates_a_number_never_a_string() {
        compare(Procs.killCommand("36642", "TERM"), ["sh", "-c", "kill -s TERM 36642"]);
    }

    function test_argv_is_read_back_with_its_separators_intact() {
        compare(Procs.parseArgv("sh\n-c\nwhile :; do :; done\n"), ["sh", "-c", "while :; do :; done"]);
        compare(Procs.parseArgv(""), []);
    }

    // The argv came from another process and can hold anything a filename
    // can, so every word is quoted before it goes near a shell.
    function test_respawn_quotes_every_argument() {
        compare(Procs.respawnCommand(["sh", "-c", "echo 'hi'"], "/home/x y"),
            ["sh", "-c", "cd '/home/x y' && exec 'sh' '-c' 'echo '\\''hi'\\'''"]);
    }

    function test_respawn_without_a_readable_cwd_still_runs() {
        compare(Procs.respawnCommand(["mpv"], ""), ["sh", "-c", "exec 'mpv'"]);
    }
}

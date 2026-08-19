import QtQuick
import QtTest
import "../shell/Monitor/collect.js" as Collect
import "../shell/Monitor/sysinfo.js" as Sysinfo

// Pure-parser coverage for the M38 system monitor (Task 1, plan decision
// D2): Collect.splitSections against bytes captured from the owner's g815
// and the mac VM rig, then every Sysinfo parser against those sections.
// Fixtures load with the same QML_XHR_ALLOW_FILE_READ=1 XHR pattern
// tst_menu_wallpaper.qml/tst_menu_emoji.qml already use for a file outside
// the test's own directory subtree.
TestCase {
    name: "MonitorSysinfo"

    property var g815: ({})
    property var vm: ({})

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
        g815 = Collect.splitSections(_load("fixtures/monitor-g815.txt"));
        vm = Collect.splitSections(_load("fixtures/monitor-vm.txt"));
    }

    // ---- splitSections ----

    function test_split_sections_finds_every_marker_on_g815() {
        var names = ["stat", "mem", "load", "uptime", "net", "temp", "disk", "drm", "nvidia", "gfx", "end"];
        for (var i = 0; i < names.length; i++)
            verify(g815[names[i]] !== undefined, names[i] + " missing");
    }

    // No supergfxctl on g815 (the switch is Intel + NVIDIA hybrid without
    // it), so the section marker is present with an empty body rather than
    // being dropped.
    function test_split_sections_leaves_an_absent_tool_section_empty() {
        compare(g815.gfx, "");
    }

    function test_split_sections_leaves_every_gpu_and_temp_section_empty_on_the_vm() {
        compare(vm.temp, "");
        compare(vm.drm, "");
        compare(vm.nvidia, "");
        compare(vm.gfx, "");
    }

    function test_split_sections_keeps_bodies_out_of_neighboring_sections() {
        verify(g815.stat.indexOf("cpu0") >= 0);
        verify(g815.stat.indexOf("@mem") < 0);
        verify(g815.mem.indexOf("MemTotal") >= 0);
    }

    // ---- parseStat / cpuDelta ----

    function test_parse_stat_reads_the_aggregate_and_per_core_lines() {
        var records = Sysinfo.parseStat(g815.stat);
        compare(records.length, 5);
        compare(records[0].label, "cpu");
        compare(records[1].label, "cpu0");
        compare(records[0].idle, 15406530);
    }

    function test_parse_stat_on_a_missing_section_is_an_empty_array() {
        compare(Sysinfo.parseStat("").length, 0);
        compare(Sysinfo.parseStat(vm.drm).length, 0);
    }

    function test_cpu_delta_is_null_with_no_previous_sample() {
        var next = Sysinfo.parseStat(g815.stat);
        compare(Sysinfo.cpuDelta(null, next), null);
        compare(Sysinfo.cpuDelta(undefined, next), null);
        compare(Sysinfo.cpuDelta([], next), null);
    }

    function test_cpu_delta_aggregate_and_per_core_fractions_are_0_to_1() {
        var prev = Sysinfo.parseStat(
            "cpu 100 0 100 700 0 0 0 0 0 0\n" +
            "cpu0 50 0 50 350 0 0 0 0 0 0\n" +
            "cpu1 50 0 50 350 0 0 0 0 0 0"
        );
        var next = Sysinfo.parseStat(
            "cpu 200 0 200 800 0 0 0 0 0 0\n" +
            "cpu0 120 0 60 370 0 0 0 0 0 0\n" +
            "cpu1 80 0 140 430 0 0 0 0 0 0"
        );
        var delta = Sysinfo.cpuDelta(prev, next);
        verify(delta !== null);
        fuzzyCompare(delta.aggregate, 200 / 300, 0.0001);
        compare(delta.cores.length, 2);
        compare(delta.cores[0].label, "cpu0");
        compare(delta.cores[0].fraction, 0.8);
        compare(delta.cores[1].label, "cpu1");
        compare(delta.cores[1].fraction, 0.6);

        verify(delta.aggregate >= 0 && delta.aggregate <= 1);
        for (var i = 0; i < delta.cores.length; i++)
            verify(delta.cores[i].fraction >= 0 && delta.cores[i].fraction <= 1);
    }

    function test_cpu_delta_is_null_when_the_total_did_not_advance() {
        var same = Sysinfo.parseStat("cpu 100 0 100 700 0 0 0 0 0 0");
        compare(Sysinfo.cpuDelta(same, same), null);
    }

    // ---- parseMem ----

    function test_parse_mem_g815_real_numbers() {
        var mem = Sysinfo.parseMem(g815.mem);
        verify(mem.available);
        compare(mem.totalBytes, 32191112 * 1024);
        compare(mem.availableBytes, 18139792 * 1024);
        compare(mem.freeBytes, 9172100 * 1024);
        compare(mem.swapTotalBytes, 16095228 * 1024);
        compare(mem.swapFreeBytes, 16090556 * 1024);
        fuzzyCompare(mem.usedFraction, (32191112 - 18139792) / 32191112, 0.0001);
    }

    function test_parse_mem_vm_is_swapless() {
        var mem = Sysinfo.parseMem(vm.mem);
        verify(mem.available);
        compare(mem.swapTotalBytes, 0);
        compare(mem.swapFreeBytes, 0);
        verify(mem.usedFraction >= 0 && mem.usedFraction <= 1);
    }

    function test_parse_mem_on_a_missing_section_is_unavailable() {
        compare(Sysinfo.parseMem("").available, false);
    }

    // ---- parseLoad / parseUptime ----

    function test_parse_load_g815() {
        var load = Sysinfo.parseLoad(g815.load);
        verify(load.available);
        compare(load.load1, 1.50);
        compare(load.load5, 1.05);
        compare(load.load15, 1.40);
        compare(load.runningProcs, 4);
        compare(load.totalProcs, 2006);
        compare(load.lastPid, 103726);
    }

    function test_parse_load_on_a_missing_section_is_unavailable() {
        compare(Sysinfo.parseLoad("").available, false);
    }

    function test_parse_uptime_g815() {
        var uptime = Sysinfo.parseUptime(g815.uptime);
        verify(uptime.available);
        compare(uptime.uptimeSeconds, 6850.34);
        compare(uptime.idleSeconds, 154065.38);
    }

    function test_parse_uptime_on_a_missing_section_is_unavailable() {
        compare(Sysinfo.parseUptime("").available, false);
    }

    // ---- parseNet / netDelta ----

    function test_parse_net_excludes_loopback() {
        var rows = Sysinfo.parseNet(g815.net);
        compare(rows.length, 2);
        for (var i = 0; i < rows.length; i++)
            verify(rows[i].iface !== "lo");
    }

    function test_parse_net_reads_rx_tx_bytes() {
        var rows = Sysinfo.parseNet(g815.net);
        var wifi = rows.filter(function (r) { return r.iface === "wlp129s0f0"; })[0];
        verify(wifi);
        compare(wifi.rxBytes, 3306453649);
        compare(wifi.txBytes, 351143584);
    }

    function test_parse_net_on_a_missing_section_is_an_empty_array() {
        compare(Sysinfo.parseNet("").length, 0);
        compare(Sysinfo.parseNet(vm.drm).length, 0);
    }

    function test_net_delta_is_null_with_no_previous_sample_or_no_elapsed_time() {
        var next = Sysinfo.parseNet(g815.net);
        compare(Sysinfo.netDelta(null, next, 1000), null);
        compare(Sysinfo.netDelta(next, next, 0), null);
    }

    function test_net_delta_computes_bytes_per_second() {
        var prev = [{ iface: "eth0", rxBytes: 1000, txBytes: 500 }];
        var next = [{ iface: "eth0", rxBytes: 3000, txBytes: 700 }];
        var delta = Sysinfo.netDelta(prev, next, 2000);
        compare(delta.length, 1);
        compare(delta[0].iface, "eth0");
        compare(delta[0].rxBytesPerSec, 1000);
        compare(delta[0].txBytesPerSec, 100);
    }

    // A negative delta means the counter reset (interface bounced), not
    // negative traffic: the row is dropped rather than reporting a
    // fabricated rate.
    function test_net_delta_skips_an_interface_whose_counters_went_backwards() {
        var prev = [{ iface: "eth0", rxBytes: 5000, txBytes: 500 }];
        var next = [{ iface: "eth0", rxBytes: 100, txBytes: 700 }];
        compare(Sysinfo.netDelta(prev, next, 1000).length, 0);
    }

    function test_net_delta_skips_an_interface_absent_from_the_previous_sample() {
        var next = [{ iface: "eth0", rxBytes: 100, txBytes: 100 }];
        compare(Sysinfo.netDelta([], next, 1000).length, 0);
    }

    // ---- parseTemps ----

    function test_parse_temps_converts_millidegrees_and_keeps_the_chip_name() {
        var rows = Sysinfo.parseTemps(g815.temp);
        var pkg = rows.filter(function (r) { return r.chip === "coretemp" && r.id === "temp1_input"; })[0];
        verify(pkg);
        compare(pkg.celsius, 62);
        compare(pkg.label, "Package id 0");
    }

    function test_parse_temps_falls_back_to_the_chip_name_when_the_label_is_empty() {
        var rows = Sysinfo.parseTemps(g815.temp);
        var wifi = rows.filter(function (r) { return r.chip === "iwlwifi_1_6"; })[0];
        verify(wifi);
        compare(wifi.label, "iwlwifi_1_6");
        compare(wifi.celsius, 56);

        var acpi = rows.filter(function (r) { return r.chip === "acpitz_0"; })[0];
        verify(acpi);
        compare(acpi.label, "acpitz_0");
    }

    function test_parse_temps_on_the_vms_hwmonless_fixture_is_empty() {
        compare(Sysinfo.parseTemps(vm.temp).length, 0);
    }

    // ---- parseDisk ----

    function test_parse_disk_reads_source_mount_size_used_and_fraction() {
        var rows = Sysinfo.parseDisk(g815.disk);
        compare(rows.length, 3);
        compare(rows[0].source, "/dev/nvme0n1p5");
        compare(rows[0].mount, "/");
        compare(rows[0].size, 269427478528);
        compare(rows[0].used, 164616077312);
        fuzzyCompare(rows[0].fraction, 164616077312 / 269427478528, 0.0001);
        verify(rows[0].fraction >= 0 && rows[0].fraction <= 1);
        compare(rows[1].source, "/dev/nvme0n1p1");
        compare(rows[1].mount, "/boot");
        compare(rows[2].source, "macbook:");
        compare(rows[2].mount, "/home/kyandesutter/.macbook");
    }

    function test_parse_disk_on_a_missing_section_is_an_empty_array() {
        compare(Sysinfo.parseDisk("").length, 0);
    }

    // The VM's disk section carries four 9p mounts that share a size
    // (certs/shared/xchg/keys) plus /dev/vda and overlay, which happen to
    // share a size too: seven genuinely different sources, so dedup must
    // change nothing here. This is the fixture the plan calls out as
    // exercising "no true duplicate", the synthetic cases below cover the
    // dedupe rule itself.
    function test_parse_disk_keeps_every_row_when_all_sources_differ() {
        var rows = Sysinfo.parseDisk(vm.disk);
        compare(rows.length, 7);
        var sources = rows.map(function (r) { return r.source; });
        compare(sources, ["/dev/vda", "certs", "shared", "xchg", "/dev/vdb", "keys", "overlay"]);
    }

    // No real capture at hand contains a true duplicate source (both
    // machines' df output above is already source-unique), so the dedupe
    // rule itself is exercised against small inline input rather than a
    // fabricated fixture.
    function test_parse_disk_dedupes_a_repeated_source_keeping_the_shortest_mount() {
        var text =
            "/dev/sda1 /mnt/data/nested 1000 500\n" +
            "/dev/sda1 /data 1000 500\n" +
            "/dev/sda2 /var 2000 1000";
        var rows = Sysinfo.parseDisk(text);
        compare(rows.length, 2);
        compare(rows[0].source, "/dev/sda1");
        compare(rows[0].mount, "/data");
        compare(rows[1].source, "/dev/sda2");
        compare(rows[1].mount, "/var");
    }

    // Same rule, reversed order: the shortest mount for a repeated source
    // can arrive first or last in df's output and the result must not
    // depend on which.
    function test_parse_disk_dedupe_does_not_depend_on_row_order() {
        var text =
            "/dev/sda1 /data 1000 500\n" +
            "/dev/sda1 /mnt/data/nested 1000 500";
        var rows = Sysinfo.parseDisk(text);
        compare(rows.length, 1);
        compare(rows[0].mount, "/data");
    }

    function test_parse_disk_size_alone_never_merges_distinct_sources() {
        var text =
            "certs /etc/ssl/certs 1000 500\n" +
            "shared /tmp/shared 1000 500";
        var rows = Sysinfo.parseDisk(text);
        compare(rows.length, 2);
    }

    // ---- the VM fixture end to end: honest-unavailable, never throws ----

    function test_every_parser_survives_the_vms_gpu_and_temp_sections_being_empty() {
        compare(Sysinfo.parseTemps(vm.temp).length, 0);

        verify(Sysinfo.parseStat(vm.stat).length > 0);
        verify(Sysinfo.parseMem(vm.mem).available);
        verify(Sysinfo.parseLoad(vm.load).available);
        verify(Sysinfo.parseUptime(vm.uptime).available);
        verify(Sysinfo.parseNet(vm.net).length > 0);
        verify(Sysinfo.parseDisk(vm.disk).length > 0);
    }
}

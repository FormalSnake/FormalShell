import QtQuick
import QtTest
import "../shell/Monitor/gpu.js" as Gpu

// Fixtures are bytes captured from real hardware (owner's g815 and e1504g
// laptops, 2026-08-19; gpu-intel-metrics.txt from e1504g on 2026-08-26,
// after the collector started reading gt_act_freq_mhz/gt_max_freq_mhz),
// except gpu-amd.txt: no AMD hardware is reachable from
// this rig, so it is hand-written to the documented amdgpu sysfs contract
// (gpu_busy_percent, mem_info_vram_used/total, hwmon temp1_input/
// power1_average) rather than a real capture. It exercises the parser only.
//
// gpu.js takes section TEXT as input (the shape shell/Monitor/collect.js's
// splitSections() would hand it), not the whole `@drm\n...\n@nvidia\n...`
// blob, so _section() below reproduces just enough of that split to load
// fixture files without depending on the sibling collect.js module.
TestCase {
    name: "MonitorGpu"

    property string hybridBlob: ""
    property string singleBlob: ""
    property string noneBlob: ""
    property string amdBlob: ""
    property string intelBlob: ""

    function _readFile(relPath) {
        var done = false;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) done = true;
        };
        xhr.open("GET", Qt.resolvedUrl(relPath));
        xhr.send();
        tryVerify(function () { return done; }, 5000);
        return xhr.responseText;
    }

    // The lines between a "@name" marker line and the next "@..." marker
    // line (or end of file), joined back with "\n": the same section text
    // splitSections() hands to parseCards/parseNvidia/parseGfxMode.
    function _section(blob, name) {
        var lines = blob.split("\n");
        var marker = "@" + name;
        var start = lines.indexOf(marker);
        if (start === -1)
            return "";
        var content = [];
        for (var i = start + 1; i < lines.length; i++) {
            if (lines[i].indexOf("@") === 0)
                break;
            content.push(lines[i]);
        }
        return content.join("\n");
    }

    function initTestCase() {
        hybridBlob = _readFile("fixtures/gpu-hybrid.txt");
        singleBlob = _readFile("fixtures/gpu-single.txt");
        noneBlob = _readFile("fixtures/gpu-none.txt");
        amdBlob = _readFile("fixtures/gpu-amd.txt");
        intelBlob = _readFile("fixtures/gpu-intel-metrics.txt");
    }

    // ---- parseCards / isDiscrete -------------------------------------

    function test_hybrid_yields_two_cards_dgpu_first_by_enumeration() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        compare(cards.length, 2);
        compare(cards[0].card, "card0");
        compare(cards[0].driver, "nvidia");
        compare(cards[1].card, "card1");
        compare(cards[1].driver, "i915");
    }

    // The point of this fixture: card0 has boot_vga=0 (discrete) and card1
    // has boot_vga=1 (integrated): numbering does not imply primacy.
    function test_hybrid_card_numbering_is_not_primacy() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        compare(Gpu.isDiscrete(cards[0]), true);
        compare(Gpu.isDiscrete(cards[1]), false);
    }

    function test_hybrid_connectors_fold_onto_their_card() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        compare(cards[0].outputs.length, 3);
        compare(cards[0].outputs[2].name, "HDMI-A-1");
        compare(cards[0].outputs[2].connected, true);
        compare(cards[1].outputs.length, 3);
        compare(cards[1].outputs[2].name, "eDP-1");
        compare(cards[1].outputs[2].connected, true);
        compare(cards[1].outputs[0].connected, false);
    }

    // e1504g's only card is card1, not card0: any code that assumes a
    // card0 exists (e.g. indexing cards[0] and expecting the integrated GPU)
    // would fail this test.
    function test_single_fixture_has_no_card0() {
        var cards = Gpu.parseCards(_section(singleBlob, "drm"));
        compare(cards.length, 1);
        compare(cards[0].card, "card1");
        compare(Gpu.isDiscrete(cards[0]), false);
    }

    function test_none_fixture_yields_zero_cards_and_does_not_throw() {
        var cards = Gpu.parseCards(_section(noneBlob, "drm"));
        compare(cards.length, 0);
        var nvidia = Gpu.parseNvidia(_section(noneBlob, "nvidia"));
        compare(nvidia.length, 0);
        var gfx = Gpu.parseGfxMode(_section(noneBlob, "gfx"));
        compare(gfx.supported, false);
        var merged = Gpu.mergeGpu(cards, Gpu.parseMetrics(_section(noneBlob, "drm")), nvidia);
        compare(merged.length, 0);
    }

    // ---- parseNvidia ----------------------------------------------------

    function test_nvidia_row_parses_g815_fixture() {
        var rows = Gpu.parseNvidia(_section(hybridBlob, "nvidia"));
        compare(rows.length, 1);
        compare(rows[0].index, 0);
        compare(rows[0].name, "NVIDIA GeForce RTX 5070 Laptop GPU");
        compare(rows[0].temperature, 50);
        compare(rows[0].power, 12.17);
    }

    function test_nvidia_utilization_16_becomes_fraction_016() {
        var rows = Gpu.parseNvidia(_section(hybridBlob, "nvidia"));
        compare(rows[0].utilization, 0.16);
    }

    // [N/A] is a real value nvidia-smi emits for laptop fan speed and must
    // parse to null, never 0 (0 would read as "fan stopped").
    function test_nvidia_na_fan_is_null_not_zero() {
        var rows = Gpu.parseNvidia(_section(hybridBlob, "nvidia"));
        compare(rows[0].fan, null);
        verify(rows[0].fan !== 0);
    }

    // ---- mergeGpu ---------------------------------------------------------

    function test_merge_attaches_nvidia_metrics_in_the_right_units() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        var nvidia = Gpu.parseNvidia(_section(hybridBlob, "nvidia"));
        var metrics = Gpu.parseMetrics(_section(hybridBlob, "drm"));
        var merged = Gpu.mergeGpu(cards, metrics, nvidia);

        var nvidiaCard = merged[0];
        compare(nvidiaCard.card, "card0");
        compare(nvidiaCard.metrics.available, true);
        compare(nvidiaCard.metrics.busy, 0.16);
        compare(nvidiaCard.metrics.tempC, 50);
        compare(nvidiaCard.metrics.powerW, 12.17);
        compare(nvidiaCard.metrics.fanPercent, null);
        compare(nvidiaCard.metrics.vramUsed, 78 * 1024 * 1024);
        compare(nvidiaCard.metrics.vramTotal, 8151 * 1024 * 1024);
    }

    // An i915 card the collector read no metric row for stays unavailable:
    // no unprivileged utilisation counter exists, so nothing is invented.
    // The hybrid fixture predates the gt_*_freq_mhz rows and carries none.
    function test_merge_i915_card_with_no_metric_rows_reports_unavailable() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        var nvidia = Gpu.parseNvidia(_section(hybridBlob, "nvidia"));
        var metrics = Gpu.parseMetrics(_section(hybridBlob, "drm"));
        var merged = Gpu.mergeGpu(cards, metrics, nvidia);

        var intelCard = merged[1];
        compare(intelCard.card, "card1");
        compare(intelCard.metrics.available, false);
        compare(intelCard.metrics.busy, null);
        compare(intelCard.metrics.tempC, null);
        compare(intelCard.metrics.clockMhz, null);
    }

    // Every record carries the same keys whatever the driver built it, so a
    // surface can read a field without branching on the driver first.
    function test_every_metrics_record_carries_the_same_keys() {
        var intel = Gpu.mergeGpu(Gpu.parseCards(_section(intelBlob, "drm")),
            Gpu.parseMetrics(_section(intelBlob, "drm")), [])[0];
        var amd = Gpu.mergeGpu(Gpu.parseCards(_section(amdBlob, "drm")),
            Gpu.parseMetrics(_section(amdBlob, "drm")), [])[0];
        compare(Object.keys(intel.metrics).sort().join(","),
            Object.keys(amd.metrics).sort().join(","));
    }

    // The clock an i915 card publishes is a real reading and reaches the
    // record; busy stays null because that driver exposes no such counter.
    function test_merge_i915_card_publishes_its_clock_when_the_collector_read_one() {
        var cards = Gpu.parseCards(_section(intelBlob, "drm"));
        var metrics = Gpu.parseMetrics(_section(intelBlob, "drm"));
        var merged = Gpu.mergeGpu(cards, metrics, []);

        compare(merged.length, 1);
        compare(merged[0].driver, "i915");
        compare(merged[0].metrics.available, true);
        compare(merged[0].metrics.busy, null);
        compare(merged[0].metrics.clockMhz, 300);
        compare(merged[0].metrics.clockMaxMhz, 1250);
        compare(merged[0].metrics.vramTotal, null);
    }

    // The card hwmon block collect.js walks for every card is not amdgpu's
    // alone: an Intel card that registers one reports its temperature,
    // power and tachometer through the same rows.
    function test_merge_non_amd_card_reads_its_card_hwmon_rows() {
        var drm = "card|card0|xe|0x8086|0x56a0|1|0000:03:00.0|\n"
            + "metric|card0|temp1_input|47000\n"
            + "metric|card0|power1_average|23000000\n"
            + "metric|card0|fan1_input|1800";
        var merged = Gpu.mergeGpu(Gpu.parseCards(drm), Gpu.parseMetrics(drm), []);

        compare(merged[0].metrics.available, true);
        compare(merged[0].metrics.tempC, 47);
        compare(merged[0].metrics.powerW, 23);
        compare(merged[0].metrics.fanRpm, 1800);
        compare(merged[0].metrics.fanPercent, null);
        compare(merged[0].metrics.busy, null);
    }

    function test_amd_fixture_yields_real_busy_fraction_and_vram_bytes() {
        var cards = Gpu.parseCards(_section(amdBlob, "drm"));
        var metrics = Gpu.parseMetrics(_section(amdBlob, "drm"));
        var merged = Gpu.mergeGpu(cards, metrics, []);

        compare(merged.length, 1);
        compare(merged[0].driver, "amdgpu");
        compare(Gpu.isDiscrete(merged[0]), true);
        compare(merged[0].metrics.available, true);
        compare(merged[0].metrics.busy, 0.37);
        compare(merged[0].metrics.vramUsed, 4294967296);
        compare(merged[0].metrics.vramTotal, 17179869184);
        compare(merged[0].metrics.tempC, 58);
        compare(merged[0].metrics.powerW, 145);
        // fan1_input off the amdgpu hwmon ABI is RPM, never a percent: the
        // amd fixture carries no fan row, so both fan keys stay null.
        compare(merged[0].metrics.fanRpm, null);
        compare(merged[0].metrics.fanPercent, null);
    }

    // ---- outputCard -------------------------------------------------------

    function test_output_card_maps_hdmi_to_the_dgpu_and_edp_to_the_igpu() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        compare(Gpu.outputCard("HDMI-A-1", cards).card, "card0");
        compare(Gpu.outputCard("HDMI-A-1", cards).driver, "nvidia");
        compare(Gpu.outputCard("eDP-1", cards).card, "card1");
        compare(Gpu.outputCard("eDP-1", cards).driver, "i915");
    }

    function test_output_card_is_null_for_an_unknown_connector() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        compare(Gpu.outputCard("DP-99", cards), null);
    }

    // ---- offloadArgv / stripFieldCodes -------------------------------------

    function test_offload_argv_uses_the_nvidia_offload_wrapper_when_available() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        var argv = Gpu.offloadArgv("firefox %u", cards[0], { nvidiaOffload: true });
        compare(argv.join(" "), "nvidia-offload sh -c firefox");
    }

    function test_offload_argv_falls_back_to_prime_run() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        var argv = Gpu.offloadArgv("firefox", cards[0], { primeRun: true });
        compare(argv.join(" "), "prime-run sh -c firefox");
    }

    function test_offload_argv_falls_back_to_the_exact_four_env_vars() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        var argv = Gpu.offloadArgv("firefox", cards[0], {});
        compare(argv.join(" "), "env __NV_PRIME_RENDER_OFFLOAD=1 " +
            "__NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0 __GLX_VENDOR_LIBRARY_NAME=nvidia " +
            "__VK_LAYER_NV_optimus=NVIDIA_only sh -c firefox");
    }

    function test_offload_argv_uses_dri_prime_pci_slot_for_a_non_nvidia_card() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        var argv = Gpu.offloadArgv("firefox", cards[1], {});
        compare(argv.join(" "), "env DRI_PRIME=pci-0000_00_02_0 sh -c firefox");
    }

    function test_strip_field_codes_removes_a_single_code() {
        compare(Gpu.stripFieldCodes("firefox %u"), "firefox");
    }

    function test_strip_field_codes_collapses_multiple_codes_cleanly() {
        compare(Gpu.stripFieldCodes("foo %F --bar %i"), "foo --bar");
    }

    function test_strip_field_codes_keeps_a_literal_percent_from_double_percent() {
        compare(Gpu.stripFieldCodes("echo 100%%"), "echo 100%");
    }

    // ---- parseGfxMode -------------------------------------------------

    function test_gfx_mode_empty_output_is_unsupported() {
        var gfx = Gpu.parseGfxMode(_section(hybridBlob, "gfx"));
        compare(gfx.supported, false);
        compare(gfx.mode, "");
    }

    function test_gfx_mode_empty_string_is_unsupported_never_integrated() {
        var gfx = Gpu.parseGfxMode("");
        compare(gfx.supported, false);
        verify(gfx.mode !== "integrated" && gfx.mode !== "Integrated");
    }

    function test_gfx_mode_strips_quotes_when_supergfxctl_answers() {
        var gfx = Gpu.parseGfxMode("\"Hybrid\"\n");
        compare(gfx.supported, true);
        compare(gfx.mode, "Hybrid");
    }
}

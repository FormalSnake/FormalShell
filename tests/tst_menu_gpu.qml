import QtQuick
import QtTest
import "../shell/Monitor/gpu.js" as Gpu
import "../shell/Menu/providers.js" as Providers

// M38 Task 8 (launch on dGPU): the gpu/gpu.launch/gpu.mode routes, over the
// same real-hardware fixtures tst_monitor_gpu.qml already loads. Card
// records are assembled with the exact same steps GpuService.qml's own
// _buildCards takes (parseCards/parseMetrics/parseNvidia/mergeGpu, then
// displayName/isDiscrete attached per card) since GpuService itself is a
// live singleton that shells out, not something a pure provider test wants
// to construct.
TestCase {
    name: "MenuGpu"

    property string hybridBlob: ""
    property string singleBlob: ""
    property string noneBlob: ""

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

    // Same section split tst_monitor_gpu.qml uses: the lines between a
    // "@name" marker and the next "@..." marker.
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

    function _buildCards(blob) {
        var cards = Gpu.parseCards(_section(blob, "drm"));
        var metrics = Gpu.parseMetrics(_section(blob, "drm"));
        var nvidiaRows = Gpu.parseNvidia(_section(blob, "nvidia"));
        var merged = Gpu.mergeGpu(cards, metrics, nvidiaRows);

        var nvidiaIndex = 0;
        return merged.map(function (card) {
            var nvidiaRow = null;
            if (card.driver === "nvidia") {
                nvidiaRow = nvidiaRows[nvidiaIndex] || null;
                nvidiaIndex++;
            }
            card.name = Gpu.displayName(card, nvidiaRow);
            card.discrete = Gpu.isDiscrete(card);
            return card;
        });
    }

    function _defaultDiscrete(cards) {
        for (var i = 0; i < cards.length; i++) {
            if (cards[i].discrete === true)
                return cards[i];
        }
        return null;
    }

    function initTestCase() {
        hybridBlob = _readFile("fixtures/gpu-hybrid.txt");
        singleBlob = _readFile("fixtures/gpu-single.txt");
        noneBlob = _readFile("fixtures/gpu-none.txt");
    }

    // ---- gpuProvider (the "gpu" route) -----------------------------------

    function test_gpu_provider_one_note_row_per_card() {
        var cards = _buildCards(hybridBlob);
        var rows = Providers.gpuProvider(cards);
        compare(rows.length, 2);
        compare(rows[0].id, "gpu.card.card0");
        compare(rows[0].kind, "note");
        compare(rows[0].label, "NVIDIA GeForce RTX 5070 Laptop GPU");
        verify(rows[0].desc.indexOf("Discrete") >= 0);
        verify(rows[0].desc.indexOf("nvidia") >= 0);
        verify(rows[0].desc.indexOf("HDMI-A-1") >= 0);
        compare(rows[1].id, "gpu.card.card1");
        verify(rows[1].desc.indexOf("Integrated") >= 0);
        verify(rows[1].desc.indexOf("eDP-1") >= 0);
    }

    function test_gpu_provider_no_cards_yields_honest_no_gpu_row() {
        var cards = _buildCards(noneBlob);
        var rows = Providers.gpuProvider(cards);
        compare(rows.length, 1);
        compare(rows[0].id, "gpu.empty");
        compare(rows[0].kind, "note");
        compare(rows[0].dim, true);
        compare(rows[0].label, "NO GPU");
    }

    // ---- gpuLaunchEntry (the "gpu.launch" route's presence) ---------------

    function test_gpu_launch_entry_present_on_hybrid_machine() {
        var cards = _buildCards(hybridBlob);
        var entries = Providers.gpuLaunchEntry(_defaultDiscrete(cards));
        verify(entries["gpu.launch"] !== undefined);
        compare(entries["gpu.launch"].provider, "gpuLaunch");
    }

    // The single-card machine has no discrete card at all (card1's own
    // boot_vga=1), so the whole route must be absent -- not present with an
    // empty child list.
    function test_gpu_launch_entry_absent_on_single_card_machine() {
        var cards = _buildCards(singleBlob);
        compare(_defaultDiscrete(cards), null);
        var entries = Providers.gpuLaunchEntry(_defaultDiscrete(cards));
        compare(Object.keys(entries).length, 0);
    }

    function test_gpu_launch_entry_absent_on_no_gpu_machine() {
        var cards = _buildCards(noneBlob);
        var entries = Providers.gpuLaunchEntry(_defaultDiscrete(cards));
        compare(Object.keys(entries).length, 0);
    }

    // ---- gpuLaunchProvider (the "gpu.launch" route's rows) -----------------

    function stubEntry(id, name) {
        return { id: id, name: name, icon: "", genericName: "" };
    }

    function test_gpu_launch_provider_rows_target_the_discrete_card() {
        var cards = _buildCards(hybridBlob);
        var card = _defaultDiscrete(cards);
        compare(card.card, "card0");
        var rows = Providers.gpuLaunchProvider([stubEntry("firefox", "Firefox")], null, [], Date.now(), "/store/share/formalshell", card.card);
        compare(rows.length, 1);
        compare(rows[0].id, "gpu.launch.firefox");
        compare(rows[0].kind, "action");
        compare(rows[0].label, "Firefox");
        compare(rows[0].action, "qs ipc -p /store/share/formalshell call monitor launch 'firefox' 'card0'");
    }

    // A desktop id carrying a single quote must not break the sh -c string
    // it lands in -- the same close/escape/reopen HyprlandBackend's
    // _quoteArg and trayProvider's rows already rely on.
    function test_gpu_launch_provider_shell_quotes_a_tricky_desktop_id() {
        var rows = Providers.gpuLaunchProvider([stubEntry("it's-an-app", "It's An App")], null, [], Date.now(), "/store/share/formalshell", "card0");
        compare(rows[0].action, "qs ipc -p /store/share/formalshell call monitor launch 'it'\\''s-an-app' 'card0'");
    }

    // ---- gpuModeEntry (the "gpu.mode" route's presence) --------------------

    function test_gpu_mode_entry_absent_when_unsupported() {
        var cards = _buildCards(hybridBlob);
        compare(Gpu.parseGfxMode(_section(hybridBlob, "gfx")).supported, false);
        var entries = Providers.gpuModeEntry("/store/share/formalshell", Gpu.parseGfxMode(_section(hybridBlob, "gfx")));
        compare(Object.keys(entries).length, 0);
    }

    function test_gpu_mode_entry_present_and_shell_quoted_when_supported() {
        var entries = Providers.gpuModeEntry("/store/share/formalshell", { supported: true, mode: "Hybrid" });
        verify(entries["gpu.mode"] !== undefined);
        compare(entries["gpu.mode.integrated"].action, "qs ipc -p /store/share/formalshell call monitor mode integrated");
        compare(entries["gpu.mode.hybrid"].action, "qs ipc -p /store/share/formalshell call monitor mode hybrid");
    }
}

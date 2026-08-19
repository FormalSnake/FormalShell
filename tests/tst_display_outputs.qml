import QtQuick
import QtTest
import "../shell/Display/outputs.js" as Outputs
import "../shell/Monitor/gpu.js" as Gpu

// DisplayPanel's output-to-card annotation (M38 Task 9). Reuses the
// gpu-hybrid.txt/gpu-single.txt fixtures tst_monitor_gpu.qml already loads
// (real bytes captured from the owner's g815 and e1504g, 2026-08-19).
// _readFile/_section below mirror that file's own loader exactly, since
// each QML test file is standalone.
TestCase {
    name: "DisplayOutputs"

    property string hybridBlob: ""
    property string singleBlob: ""

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
    }

    // g815: the external HDMI is wired to the dGPU (card0, nvidia).
    function test_hybrid_hdmi_reads_discrete_nvidia() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        compare(Outputs.outputCardLabel("HDMI-A-1", cards), "NVIDIA / DISCRETE");
    }

    // g815: the internal panel is wired to the iGPU (card1, i915,
    // boot_vga=1). Card numbering does not imply which one that is.
    function test_hybrid_edp_reads_integrated_intel() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        compare(Outputs.outputCardLabel("eDP-1", cards), "Intel / INTEGRATED");
    }

    // A connector no card claims (typoed name, a third monitor plugged into
    // neither known card) renders no annotation, never a guess.
    function test_hybrid_unknown_connector_yields_no_annotation() {
        var cards = Gpu.parseCards(_section(hybridBlob, "drm"));
        compare(Outputs.outputCardLabel("DP-99", cards), "");
    }

    // e1504g: one card. Annotating the row with the only card on the
    // machine is noise, so the panel looks exactly as it does today there.
    function test_single_card_suppresses_annotation() {
        var cards = Gpu.parseCards(_section(singleBlob, "drm"));
        compare(cards.length, 1);
        compare(Outputs.outputCardLabel("eDP-1", cards), "");
    }

    // No GPU at all (the mac VM) is the same suppression path as one card.
    function test_no_cards_suppresses_annotation() {
        compare(Outputs.outputCardLabel("eDP-1", []), "");
    }
}

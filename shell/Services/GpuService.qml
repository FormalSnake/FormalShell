pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services
import "../Monitor/gpu.js" as Gpu

// GPU enumeration and metrics (M38 Task 4, plan decisions D2/D3). Rides
// SystemMonitorService's own collector tick instead of running a second
// `sh -c` Process: the @drm/@nvidia/@gfx sections this needs already sit in
// the SAME blob SystemMonitorService parses for CPU/mem every tick (D2's
// whole point is one collector run per poll, not N), so a second Process
// here would just double the syscalls for data already carried on that
// signal. refresh() and Component.onCompleted both pulse
// SystemMonitorService's own subscribe()/unsubscribe(): a 0->1->0
// transition triggers exactly one immediate tick, the same contract a real
// subscriber joining from zero gets, rather than holding a permanent
// subscription open, so card enumeration costs one collector run at
// startup and on explicit refresh, never a standing poll of its own. Live
// metrics keep updating only for as long as something else (the bar cell,
// panel, or launcher view) is actually subscribed.
//
// A machine with no GPU at all (the mac VM: /sys/class/drm holds no cards)
// is a normal state: cards stays [], available is false, nothing warns.
Singleton {
    id: root

    property var cards: []
    readonly property bool available: root.cards.length > 0
    property var gfxMode: ({ supported: false, mode: "" })

    // Which offload wrapper is on PATH, in offloadArgv's expected shape.
    // Probed once at startup; a PATH that changes mid-session (installing
    // nvidia-offload without restarting the shell) is not re-checked.
    property var tools: ({ nvidiaOffload: false, primeRun: false })

    function refresh() {
        SystemMonitorService.subscribe();
        SystemMonitorService.unsubscribe();
    }

    function cardById(id) {
        for (var i = 0; i < root.cards.length; i++) {
            if (root.cards[i].card === id)
                return root.cards[i];
        }
        return null;
    }

    // First card with boot_vga=0 (isDiscrete), or null on a single-GPU or
    // no-GPU machine. Never the first entry by array position: card
    // numbering does not imply primacy (gpu.js's own header, pinned by the
    // g815 fixture: the dGPU enumerates as card0 with boot_vga=0, the iGPU
    // as card1 with boot_vga=1).
    function defaultDiscrete() {
        for (var i = 0; i < root.cards.length; i++) {
            if (root.cards[i].discrete === true)
                return root.cards[i];
        }
        return null;
    }

    // The display name of the card driving `connector` (a compositor
    // output name, e.g. "eDP-1"), or "" when no card claims it, never a
    // guess.
    function outputCardName(connector) {
        var card = Gpu.outputCard(connector, root.cards);
        return card ? card.name : "";
    }

    // Mirrors mergeGpu's own "nvidia rows matched to nvidia-driver cards in
    // enumeration order" (gpu.js) to also resolve each card's display
    // name: mergeGpu folds a matched row into `metrics` and drops the name
    // nvidia-smi reported, so that match has to be redone here.
    function _buildCards(sections) {
        var parsedCards = Gpu.parseCards(sections.drm);
        var metrics = Gpu.parseMetrics(sections.drm);
        var nvidiaRows = Gpu.parseNvidia(sections.nvidia);
        var merged = Gpu.mergeGpu(parsedCards, metrics, nvidiaRows);

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

    Connections {
        target: SystemMonitorService
        function onTick(sections) {
            root.cards = root._buildCards(sections);
            root.gfxMode = Gpu.parseGfxMode(sections.gfx);
        }
    }

    Component.onCompleted: {
        toolsProc.running = true;
        root.refresh();
    }

    Process {
        id: toolsProc
        command: ["sh", "-c", "command -v nvidia-offload >/dev/null 2>&1 && echo nvidia-offload; command -v prime-run >/dev/null 2>&1 && echo prime-run"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split("\n");
                root.tools = {
                    nvidiaOffload: lines.indexOf("nvidia-offload") !== -1,
                    primeRun: lines.indexOf("prime-run") !== -1
                };
            }
        }
    }
}

.pragma library

// Pure GPU parsing for the system monitor and dGPU-offload launch (M38 Task
// 2). No Quickshell/Process/XHR access here — SystemMonitorService/GpuService
// collect the bytes (the D2 collector's @drm/@nvidia/@gfx sections) and this
// module turns them into records, tested head-on against bytes captured from
// real hardware (tests/fixtures/gpu-*.txt).
//
// Card ids (`card0`, `card1`, ...) are opaque strings end to end, same rule
// as compositor window/workspace ids (CLAUDE.md): the collector's own card
// numbering does not imply which GPU is primary. `boot_vga` is the only
// signal for that (see isDiscrete). The owner's g815 fixture pins this: the
// dGPU enumerates as card0 with boot_vga=0, the iGPU as card1 with
// boot_vga=1.

// ---- @drm section --------------------------------------------------------

// `card|<card>|<driver>|<vendor>|<device>|<boot_vga>|<pci>|<label>` and
// `conn|<card>|<connector>|<status>` rows, in collector emission order.
// `metric|` rows are parseMetrics()'s concern, ignored here.
// Desktop-entry Exec field codes, per the freedesktop spec. "%%" is a
// literal percent and is not one of them.
var FIELD_CODES = "fFuUickdDnNvm";

function parseCards(drmText) {
    var cards = [];
    var byId = {};
    var lines = String(drmText || "").split("\n");

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line === "")
            continue;
        var parts = line.split("|");

        if (parts[0] === "card") {
            var card = {
                card: parts[1] || "",
                driver: parts[2] || "",
                vendorId: parts[3] || "",
                deviceId: parts[4] || "",
                bootVga: parts[5] || "",
                pci: parts[6] || "",
                label: parts[7] || "",
                outputs: []
            };
            byId[card.card] = card;
            cards.push(card);
        } else if (parts[0] === "conn") {
            var target = byId[parts[1]];
            if (target) {
                target.outputs.push({
                    name: parts[2] || "",
                    connected: parts[3] === "connected"
                });
            }
        }
    }
    return cards;
}

// `{ "<card>": { "<key>": <number>, ... } }` from `metric|<card>|<key>|<value>`
// rows. A row whose value doesn't parse as a number is dropped rather than
// stored as a fabricated 0.
function parseMetrics(drmText) {
    var metrics = {};
    var lines = String(drmText || "").split("\n");

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line === "")
            continue;
        var parts = line.split("|");
        if (parts[0] !== "metric")
            continue;

        var n = Number(parts[3]);
        if (!isFinite(n))
            continue;
        var card = parts[1] || "";
        if (!metrics[card])
            metrics[card] = {};
        metrics[card][parts[2] || ""] = n;
    }
    return metrics;
}

// ---- @nvidia section -------------------------------------------------------

function _numOrNull(field) {
    if (field === undefined || field === "[N/A]" || field === "N/A")
        return null;
    var n = Number(field);
    return isFinite(n) ? n : null;
}

// `nvidia-smi --query-gpu=index,name,utilization.gpu,temperature.gpu,
// memory.used,memory.total,power.draw,fan.speed --format=csv,noheader,
// nounits` output, one GPU per line. `[N/A]` is a value nvidia-smi really
// emits (laptop GPUs report no fan reading) and must parse to null, never 0.
// `utilization` is normalized to a 0..1 fraction here (repo convention);
// `memUsed`/`memTotal` stay in the wire's MiB — mergeGpu is what needs bytes.
function parseNvidia(nvidiaText) {
    var rows = [];
    var lines = String(nvidiaText || "").split("\n");

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line === "")
            continue;
        var fields = line.split(",").map(function (f) { return f.trim(); });
        if (fields.length < 8)
            continue;

        var util = _numOrNull(fields[2]);
        rows.push({
            index: parseInt(fields[0], 10) || 0,
            name: fields[1],
            utilization: util === null ? null : util / 100,
            temperature: _numOrNull(fields[3]),
            memUsed: _numOrNull(fields[4]),
            memTotal: _numOrNull(fields[5]),
            power: _numOrNull(fields[6]),
            fan: _numOrNull(fields[7])
        });
    }
    return rows;
}

// ---- merge ------------------------------------------------------------

function _cloneCard(card) {
    return {
        card: card.card, driver: card.driver, vendorId: card.vendorId,
        deviceId: card.deviceId, bootVga: card.bootVga, pci: card.pci,
        label: card.label, outputs: card.outputs
    };
}

function _nvidiaMetrics(row) {
    return {
        available: true,
        busy: row.utilization,
        tempC: row.temperature,
        vramUsed: row.memUsed === null ? null : row.memUsed * 1024 * 1024,
        vramTotal: row.memTotal === null ? null : row.memTotal * 1024 * 1024,
        powerW: row.power,
        fanPercent: row.fan
    };
}

function _amdMetrics(values) {
    if (!values)
        return { available: false };
    return {
        available: true,
        busy: values.gpu_busy_percent === undefined ? null : values.gpu_busy_percent / 100,
        tempC: values.temp1_input === undefined ? null : values.temp1_input / 1000,
        vramUsed: values.mem_info_vram_used === undefined ? null : values.mem_info_vram_used,
        vramTotal: values.mem_info_vram_total === undefined ? null : values.mem_info_vram_total,
        powerW: values.power1_average === undefined ? null : values.power1_average / 1000000,
        // fan1_input, when the collector gathers it, is RPM off the amdgpu
        // hwmon ABI, not a percent — there is no percent-scale fan reading
        // in this row, so this stays null instead of mislabeling an RPM.
        fanPercent: null
    };
}

// Attaches a `metrics` object to each card. NVIDIA rows are matched to
// `nvidia`-driver cards in enumeration order (both lists are already the
// collector's own emission order). amdgpu reads gpu_busy_percent (0..100,
// divided) and mem_info_vram_* (bytes already) off `metrics`. Every other
// driver (i915, xe, ...) gets `{available:false}` and nothing else — no
// unprivileged utilisation counter exists for those, and inventing one would
// violate the honest-unavailable-state rule.
function mergeGpu(cards, metrics, nvidiaRows) {
    var rows = Array.isArray(nvidiaRows) ? nvidiaRows : [];
    var byCard = metrics || {};
    var nvidiaIndex = 0;

    return (cards || []).map(function (card) {
        var record = _cloneCard(card);
        if (card.driver === "nvidia") {
            var row = rows[nvidiaIndex];
            nvidiaIndex++;
            record.metrics = row ? _nvidiaMetrics(row) : { available: false };
        } else if (card.driver === "amdgpu") {
            record.metrics = _amdMetrics(byCard[card.card]);
        } else {
            record.metrics = { available: false };
        }
        return record;
    });
}

// ---- naming -------------------------------------------------------------

function vendorName(vendorId) {
    switch (String(vendorId || "").toLowerCase()) {
    case "0x8086": return "Intel";
    case "0x1002":
    case "0x1022": return "AMD";
    case "0x10de": return "NVIDIA";
    case "0x1af4": return "virtio";
    default: return "";
    }
}

// nvidia-smi's marketing name when there is one, else the ACPI label
// ("Onboard - Video" on Intel, empty on NVIDIA), else "<vendor> <deviceId>",
// else the card id itself.
function displayName(card, nvidiaRow) {
    if (nvidiaRow && nvidiaRow.name)
        return nvidiaRow.name;
    if (card.label)
        return card.label;
    var vendor = vendorName(card.vendorId);
    if (vendor)
        return vendor + " " + card.deviceId;
    return card.card;
}

// boot_vga is the only signal for which card is the integrated/primary one —
// never the card number (the g815 fixture has the dGPU at card0).
function isDiscrete(card) {
    return card.bootVga !== "1";
}

// The card record driving `connectorName` (compositor output names —
// "eDP-1", "HDMI-A-1" — match connector names verbatim), or null.
function outputCard(connectorName, cards) {
    var list = cards || [];
    for (var i = 0; i < list.length; i++) {
        var outputs = list[i].outputs || [];
        for (var j = 0; j < outputs.length; j++) {
            if (outputs[j].name === connectorName)
                return list[i];
        }
    }
    return null;
}

// ---- launch-on-dGPU (M38 D4) ----------------------------------------------

// Exec field codes (%f %F %u %U %i %c %k %d %D %n %N %v %m) removed and
// whitespace collapsed. %% is a literal percent, protected first so it
// survives as one "%" rather than being eaten by the field-code strip.
function stripFieldCodes(execString) {
    var text = String(execString || "");
    // One pass, so a literal "%%" can never be re-read as the start of a
    // field code. A sentinel round trip would need a byte that cannot appear
    // in an Exec line, and there isn't one.
    text = text.replace(/%(.)/g, function (match, code) {
        if (code === "%")
            return "%";
        return FIELD_CODES.indexOf(code) >= 0 ? "" : match;
    });
    return text.replace(/\s+/g, " ").trim();
}

// The argv to spawn an app on `target` (a card record from mergeGpu/
// parseCards). `DesktopEntry.execute()` cannot carry an environment, so this
// builds the argv by hand instead. `tools` is `{nvidiaOffload, primeRun}` —
// what offload helper is on PATH.
//
// NVIDIA: nvidia-offload (NixOS) if present, else prime-run (Arch), else the
// exact four env vars NixOS's own nvidia-offload wrapper exports (read off
// the owner's g815, 2026-08-19). Non-NVIDIA: DRI_PRIME set to the card's PCI
// slot in Mesa's `pci-0000_02_00_0` form — never the positional `DRI_PRIME=1`,
// ambiguous on a box with more than two GPUs.
function offloadArgv(execString, target, tools) {
    var opts = tools || {};
    var tail = ["sh", "-c", stripFieldCodes(execString)];

    if (target && target.driver === "nvidia") {
        if (opts.nvidiaOffload)
            return ["nvidia-offload"].concat(tail);
        if (opts.primeRun)
            return ["prime-run"].concat(tail);
        return [
            "env",
            "__NV_PRIME_RENDER_OFFLOAD=1",
            "__NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0",
            "__GLX_VENDOR_LIBRARY_NAME=nvidia",
            "__VK_LAYER_NV_optimus=NVIDIA_only"
        ].concat(tail);
    }

    var pci = String((target && target.pci) || "").replace(/[:.]/g, "_");
    return ["env", "DRI_PRIME=pci-" + pci].concat(tail);
}

// ---- @gfx section -----------------------------------------------------

// supergfxctl's `-g` reply. Empty/absent output (no supergfxctl installed)
// means unsupported, never a guessed "integrated".
function parseGfxMode(gfxText) {
    var text = String(gfxText || "").trim();
    if (text === "")
        return { supported: false, mode: "" };
    return { supported: true, mode: text.replace(/^"|"$/g, "") };
}

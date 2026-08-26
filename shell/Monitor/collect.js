.pragma library

// The one-shot `sh -c` collector for the system monitor (M38 Task 1, plan
// decision D2): every /proc and /sys read the monitor needs in ONE process
// per poll tick, instead of N FileViews: procfs defeats FileView's change
// watching, and /sys/class/drm|hwmon need globbing QML has no primitive
// for. Section markers (`@stat`, `@mem`, ...) let one parse pass split the
// blob before Monitor/sysinfo.js and Monitor/gpu.js touch it; splitSections
// below is that pass. Exact bytes verified against the owner's g815 and the
// mac VM rig on 2026-08-19 (see tests/fixtures/monitor-*.txt).
//
// Task 2's GPU parsers read the @drm/@nvidia/@gfx sections this module
// also collects, so those section names and their row shapes must stay
// byte-identical to what's below.
//
// @fan carries the same `chip|file|label|value` row shape as @temp: hwmon
// exposes tachometers under fan*_input beside the temp*_input sensors, and
// on a laptop those are separate chips from the thermal ones (acpi_fan's
// single tacho, asus's labelled cpu_fan/gpu_fan), so globbing for them is a
// second pass over the same directory rather than more fields on a temp row.
//
// gt_act_freq_mhz/gt_max_freq_mhz sit on the CARD directory, not on
// `$c/device` where the amdgpu counters live, which is why they need a loop
// of their own. They are the only unprivileged load signal an i915/xe card
// has: those drivers expose no busy counter at all (Monitor/gpu.js's
// mergeGpu), and a clock against its own ceiling is a real reading rather
// than a utilisation figure inferred from one.
var COLLECTOR_SCRIPT = [
    'echo "@stat"; grep -E \'^cpu\' /proc/stat',
    'echo "@mem"; grep -E \'^(MemTotal|MemAvailable|MemFree|SwapTotal|SwapFree):\' /proc/meminfo',
    'echo "@load"; cat /proc/loadavg',
    'echo "@uptime"; cat /proc/uptime',
    'echo "@net"; tail -n +3 /proc/net/dev',
    'echo "@temp"; for h in /sys/class/hwmon/hwmon*; do [ -d "$h" ] || continue; n=$(cat "$h/name" 2>/dev/null); for t in "$h"/temp*_input; do [ -r "$t" ] || continue; b=$(basename "$t"); l="${t%_input}_label"; echo "$n|$b|$(cat "$l" 2>/dev/null)|$(cat "$t" 2>/dev/null)"; done; done',
    'echo "@fan"; for h in /sys/class/hwmon/hwmon*; do [ -d "$h" ] || continue; n=$(cat "$h/name" 2>/dev/null); for t in "$h"/fan*_input; do [ -r "$t" ] || continue; b=$(basename "$t"); l="${t%_input}_label"; echo "$n|$b|$(cat "$l" 2>/dev/null)|$(cat "$t" 2>/dev/null)"; done; done',
    'echo "@disk"; df -B1 -x tmpfs -x devtmpfs -x efivarfs --output=source,target,size,used 2>/dev/null | tail -n +2',
    'echo "@drm"; for c in /sys/class/drm/card*; do case "$(basename "$c")" in card[0-9]|card[0-9][0-9]) ;; *) continue ;; esac; d="$c/device"; echo "card|$(basename "$c")|$(basename "$(readlink -f "$d/driver" 2>/dev/null)")|$(cat "$d/vendor" 2>/dev/null)|$(cat "$d/device" 2>/dev/null)|$(cat "$d/boot_vga" 2>/dev/null)|$(basename "$(readlink -f "$d")")|$(cat "$d/label" 2>/dev/null)"; for f in gpu_busy_percent mem_info_vram_used mem_info_vram_total mem_busy_percent; do [ -r "$d/$f" ] && echo "metric|$(basename "$c")|$f|$(cat "$d/$f")"; done; for f in gt_act_freq_mhz gt_max_freq_mhz; do [ -r "$c/$f" ] && echo "metric|$(basename "$c")|$f|$(cat "$c/$f")"; done; for hw in "$d"/hwmon/hwmon*; do [ -d "$hw" ] || continue; for t in "$hw"/temp1_input "$hw"/power1_average "$hw"/fan1_input; do [ -r "$t" ] && echo "metric|$(basename "$c")|$(basename "$t")|$(cat "$t")"; done; done; for k in "$c"-*; do [ -d "$k" ] || continue; echo "conn|$(basename "$c")|$(basename "$k" | sed "s/^card[0-9]*-//")|$(cat "$k/status" 2>/dev/null)"; done; done',
    'echo "@nvidia"; command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=index,name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,fan.speed --format=csv,noheader,nounits 2>/dev/null',
    'echo "@gfx"; command -v supergfxctl >/dev/null 2>&1 && timeout 1 supergfxctl -g 2>/dev/null',
    'echo "@end"'
].join("\n");

// argv for Process.command: the collector never takes arguments, so this
// is a fixed two-element convenience the poller doesn't have to restate.
function collectCommand() {
    return ["sh", "-c", COLLECTOR_SCRIPT];
}

// Splits one collector run's stdout into { stat: "...", mem: "...", ... }
// keyed by marker name with the leading "@" stripped, each value the
// section's body joined back with "\n" (no trailing marker line, no
// leading/trailing blank line beyond what the source produced). A section
// with nothing between its marker and the next one (@gfx when
// supergfxctl is absent, every section on a machine with no matching
// hardware) comes back as "", not an absent key, so callers can always
// index the result without a fallback.
function splitSections(blob) {
    var sections = {};
    var lines = (typeof blob === "string" ? blob : "").split("\n");
    var current = null;
    var buffer = [];

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line.charAt(0) === "@") {
            if (current !== null)
                sections[current] = buffer.join("\n");
            current = line.slice(1);
            buffer = [];
        } else if (current !== null) {
            buffer.push(line);
        }
    }
    if (current !== null)
        sections[current] = buffer.join("\n");

    return sections;
}

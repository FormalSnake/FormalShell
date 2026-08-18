pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../Dualsense/model.js" as DualsenseModel

// Read-only sysfs bridge for a Sony DualSense controller (M29 Task 4, plan
// at docs/superpowers/plans/2026-08-18-m29-device-panels.md). No daemon:
// hid-playstation publishes battery under
// /sys/class/power_supply/ps-controller-battery-<MAC>/ (`capacity`,
// `status`), the lightbar under /sys/class/leds/input<N>:rgb:indicator/
// (`multi_intensity`, "R G B"), and player LEDs as five sibling nodes,
// input<N>:white:player-1..5/brightness. <MAC> and <N> both drift across
// reconnects (a fresh input index, a different paired controller), so
// `_probeScript` globs both — first match wins, same caveat the plan's
// research block calls out — in a single `sh -c` exec rather than five
// separate Process round trips. The lightbar and player-LED nodes share one
// index, so `<N>` is read once (off the lightbar match) and reused for all
// five player files, never globbed a second time.
//
// The shell never writes any of this: the owner's host units already own
// the lightbar/player-LED sysfs writes (dualsense-sync, outside this repo),
// and this service's only job is describing what's currently there.
//
// No standing poll: `_refCount` tracks how many consumers currently care
// (the bar widget, for as long as it's instantiated at all — it only
// exists when "dualsense" is actually in bar.layout — and the panel, for as
// long as it's open), and the 30s timer this milestone's `dualsense-bar`
// command module used to run on its own only runs while that count is
// above zero.
Singleton {
    id: root

    property bool present: false
    property var battery: DualsenseModel.parseSupply("", "")
    property var lightbar: null // "#rrggbb" or null
    property var playerLeds: null // 0-5 lit count, or null when unreadable

    property int _refCount: 0

    function acquire() {
        root._refCount++;
        if (root._refCount === 1) {
            root.probe();
            pollTimer.restart();
        }
    }

    function release() {
        root._refCount = Math.max(0, root._refCount - 1);
        if (root._refCount === 0)
            pollTimer.stop();
    }

    function probe() {
        if (proc.running)
            return;
        proc.command = ["sh", "-c", root._probeScript];
        proc.running = true;
    }

    Timer {
        id: pollTimer
        interval: 30000
        repeat: true
        onTriggered: root.probe()
    }

    // One line per field, "KEY=value" — a format this file fully controls
    // (never anything sourced from omarchy-pods; DualSense has no plugin
    // equivalent to port from anyway), so `_field` below can pull each
    // piece back out unambiguously. Every step degrades honestly: no
    // battery match means no CAP/STATUS lines at all (root.present stays
    // false), no lightbar match means no RGB/P<n> lines either.
    readonly property string _probeScript:
        'b=$(ls -d /sys/class/power_supply/ps-controller-battery-*/ 2>/dev/null | head -n1); ' +
        'if [ -n "$b" ]; then ' +
        'echo "CAP=$(cat "${b}capacity" 2>/dev/null)"; ' +
        'echo "STATUS=$(cat "${b}status" 2>/dev/null)"; ' +
        'fi; ' +
        'l=$(ls -d /sys/class/leds/input*:rgb:indicator/ 2>/dev/null | head -n1); ' +
        'if [ -n "$l" ]; then ' +
        'echo "RGB=$(cat "${l}multi_intensity" 2>/dev/null)"; ' +
        'base=${l%:rgb:indicator/}; ' +
        'for i in 1 2 3 4 5; do ' +
        'f="${base}:white:player-$i/brightness"; ' +
        'if [ -f "$f" ]; then echo "P$i=$(cat "$f" 2>/dev/null)"; fi; ' +
        'done; ' +
        'fi; ' +
        'exit 0'

    function _field(text, key) {
        var re = new RegExp("^" + key + "=(.*)$", "m");
        var m = re.exec(text);
        return m ? m[1] : "";
    }

    Process {
        id: proc
        stdout: StdioCollector {
            id: collector
        }
        onExited: exitCode => {
            var text = collector.text;
            root.battery = DualsenseModel.parseSupply(root._field(text, "CAP"), root._field(text, "STATUS"));
            root.present = root.battery.percent >= 0;

            var rgb = root._field(text, "RGB");
            if (rgb === "") {
                root.lightbar = null;
                root.playerLeds = null;
                return;
            }
            root.lightbar = DualsenseModel.parseLightbar(rgb);
            var leds = [];
            for (var i = 1; i <= 5; i++) {
                var v = root._field(text, "P" + i);
                leds.push(v !== "" ? v : null);
            }
            root.playerLeds = DualsenseModel.parsePlayerLeds(leds);
        }
    }
}

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core

// Opt-in night light (M16 Task 6, laptop feature parity with omarchy — that
// shell drives Hyprland's own hyprsunset IPC directly; this compositor has
// no equivalent, so wlsunset (wlr-gamma-control-unstable-v1) plays the same
// role as a plain Process). `nightlight.startOn` (settings.json, default
// **false**) is read once at boot (Component.onCompleted, IdleService's
// _armMonitor idiom) rather than kept live, so a later settings.json edit
// never fights a user's own enable()/disable() calls mid-session.
//
// "Fixed-temp mode, not schedule": wlsunset has no such mode on its own —
// every run needs either geo coordinates or manual sunrise/sunset, and
// normally cycles day/night temperature by wall clock. Verified against the
// pinned 0.4.0 source (kennylevinsen/wlsunset, main.c/wlsunset.1.scd) rather
// than guessed: its own documented RUNTIME CONTROL section says sending it
// SIGUSR1 cycles OFF -> forced-high -> forced-low -> OFF (automatic), each
// transition unconditionally fprintf'd to stderr ("forcing high
// temperature" / "forcing low temperature"). Sending it twice pins the low
// temperature permanently, bypassing the sun calculation entirely — exactly
// "fixed-temp", using the tool's own sanctioned mechanism rather than
// fighting it with a zero-length manual sunset/sunrise window. Dummy manual
// -S/-s times are passed only to route around wlsunset's geo-validation
// branch (config.manual_time gates it; without either manual or geo flags,
// latitude/longitude default to NaN, which the validation silently accepts
// and would feed into a live sun-position calculation for the brief instant
// before the forced state lands — no reason to depend on that when the
// values are about to be overridden anyway). Each SIGUSR1 is sent only
// after the previous one's own stderr confirmation line: standard signals
// aren't queued, so a blind double-send risks the second one coalescing
// with the first before wlsunset's handler has run. The handler installs
// before any Wayland setup (setup_signals() runs first in wlrun()), so the
// fork/exec-to-handler race this would otherwise need to guard against is
// not a real concern here.
Singleton {
    id: root

    readonly property bool active: proc.running
    property string lastError: ""
    readonly property int temp: Core.Config.get("nightlight.temp", 4000)

    property bool _sawExit: false
    property bool _intentionalStop: false
    // "" (idle), "awaiting-high" (SIGUSR1 #1 sent, waiting for wlsunset's
    // own confirmation before sending #2), "awaiting-low" (#2 sent).
    property string _phase: ""
    property string _lastStderrLine: ""

    function enable() {
        if (proc.running)
            return;
        root.lastError = "";
        root._phase = "awaiting-high";
        proc.command = ["wlsunset", "-t", String(root.temp), "-S", "06:00", "-s", "18:00"];
        proc.running = true;
    }

    function disable() {
        if (!proc.running)
            return;
        root._intentionalStop = true;
        root._phase = "";
        proc.running = false;
    }

    function toggle() {
        if (proc.running)
            root.disable();
        else
            root.enable();
    }

    function _onStderrLine(line) {
        root._lastStderrLine = line;
        if (root._phase === "awaiting-high" && line.indexOf("forcing high temperature") !== -1) {
            root._phase = "awaiting-low";
            proc.signal(10); // SIGUSR1: forced-high -> forced-low
        } else if (root._phase === "awaiting-low" && line.indexOf("forcing low temperature") !== -1) {
            root._phase = "";
        }
    }

    function _armStartOn() {
        if (Core.Config.get("nightlight.startOn", false) === true)
            root.enable();
    }

    Component.onCompleted: {
        if (Core.Config.loaded)
            root._armStartOn();
    }

    Connections {
        target: Core.Config
        function onLoadedChanged() {
            if (Core.Config.loaded)
                root._armStartOn();
        }
    }

    // Sent once, shortly after the process comes up — see the header
    // comment for why the race this guards against is already negligible;
    // this is defense in depth, not the primary safety net (the stderr
    // confirmation above is).
    Timer {
        id: armTimer
        interval: 150
        onTriggered: {
            if (proc.running && root._phase === "awaiting-high")
                proc.signal(10); // SIGUSR1: automatic -> forced-high
        }
    }

    Process {
        id: proc

        stderr: SplitParser {
            onRead: line => root._onStderrLine(line)
        }

        onRunningChanged: {
            if (proc.running) {
                root._sawExit = false;
                armTimer.restart();
            } else {
                // quickshell's Process never emits `exited` when the
                // command fails to start (CommandModule.qml's own learned
                // idiom: onErrorOccurred only emits runningChanged for
                // FailedToStart) — `wlsunset` missing from PATH lands here,
                // never in onExited below.
                if (!root._sawExit && !root._intentionalStop)
                    root.lastError = "wlsunset not found (failed to start)";
                root._intentionalStop = false;
                root._phase = "";
            }
        }

        onExited: exitCode => {
            root._sawExit = true;
            if (exitCode !== 0 && !root._intentionalStop)
                root.lastError = root._lastStderrLine || ("wlsunset exited " + exitCode);
        }
    }
}

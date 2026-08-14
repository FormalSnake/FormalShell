pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Notifications
import "../Menu/providers.js" as Providers

// Runs the menu's clipssh route and reports how it went.
//
// clipssh reads the clipboard image, pipes it over ssh, and wl-copy's the
// remote path back, so a transfer takes as long as the link does, and it can
// fail at either end. The shell runs it here rather than handing it to
// CompositorService.spawn (the path every other menu action takes) because a
// spawned command yields no exit code and no output: an in-flight transfer
// and one that died on the first line look identical from the bar.
//
// Three things say so: an indicator cell for as long as it is in flight
// (Indicators.qml, the row that means "something is happening right now"), a
// toast naming the remote path when it lands, and an urgent toast carrying
// clipssh's own error line when it doesn't.
//
// The alias goes through `sh -c` as an argument rather than spliced into the
// command, so a clipssh that isn't installed comes back as exit 127, which is
// an outcome to report, instead of a Process that never starts and so never
// exits.
//
// One transfer at a time, refused rather than queued: clipssh reads the
// clipboard at the moment it runs, and the clipboard is a single global, so a
// queued transfer would send whatever happened to be on it by then.
Singleton {
    id: root

    readonly property bool busy: proc.running

    // The alias in flight, for the indicator cell's tooltip. Empty whenever
    // `busy` is false.
    property string target: ""

    function send(alias) {
        if (String(alias || "") === "")
            return;
        if (root.busy) {
            NotificationService.notify("CLIPSSH BUSY", "Still sending to " + root.target, 1);
            return;
        }
        root.target = alias;
        proc.command = ["sh", "-c", 'exec clipssh "$1"', "sh", alias];
        proc.running = true;
        NotificationService.notify("CLIPSSH SENDING", "Clipboard image to " + alias, 1);
    }

    Process {
        id: proc

        stdout: StdioCollector {
            id: sendOut
        }
        stderr: StdioCollector {
            id: sendErr
        }

        onExited: exitCode => {
            var outcome = Providers.clipsshOutcome(exitCode, sendOut.text, sendErr.text);
            if (outcome.ok)
                NotificationService.notify("CLIPSSH COPIED",
                    outcome.path === ""
                        ? "Remote path is on the clipboard"
                        : outcome.path + " is on the clipboard", 1);
            else
                NotificationService.notify("CLIPSSH FAILED", root.target + ": " + outcome.error, 2);
            root.target = "";
        }
    }
}

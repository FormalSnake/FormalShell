import Quickshell
import Quickshell.Io
import QtQuick

import qs.Core
import qs.Notifications

// `qs ipc call screenshot full|region|cancel|status` (M12 Task 9, M13 Task 7):
// grim writes <screenshot.directory>/screenshot-<timestamp>.png (slurp
// supplies the geometry for `region`), wl-copy puts the same PNG on the
// clipboard, and a SCREENSHOT SAVED notification fires through the shell's
// own NotificationService so there is visible feedback without any bar
// surface. IpcHandler replies are synchronous QMetaMethod invocations
// (quickshell src/io/ipchandler.cpp) and slurp blocks on user interaction
// indefinitely, so full()/region() reply with the destination path the
// capture is writing toward; a runtime failure (grim error, slurp failing to
// start) lands in a SCREENSHOT FAILED notification, a console.warn, and
// status()'s lastError: loud and queryable, never a silent no-op.
//
// Region UX (M13 Task 7, from the e1504g trial where a bare slurp sat
// invisible for over an hour): slurp gets a dim theme-background overlay, an
// accent border at Theme.borderWidth, a transparent selection, and -d
// dimension readout, so pressing the bind visibly changes the screen
// immediately. Colors ride the Process environment, resolved at call time
// (matugen-current). slurp runs as its own Process — sh exec's straight into
// it, so `running = false`'s SIGTERM (quickshell src/io/process.cpp
// setRunning) lands on slurp itself, not a wrapper — and hands its geometry
// to the grim pipeline on exit 0. Exit 1 is slurp's own cancel exit (Escape/
// right-click): a cancel, not an error, so no toast. A watchdog auto-cancels
// an unanswered region selection after screenshot.timeoutSeconds (default
// 90) with a SCREENSHOT CANCELLED notification; the `cancel` verb does the
// same on demand. Scope root, not a bare IpcHandler: IpcHandler has no
// default property, so the capture Processes can't live inside it.
Scope {
    id: root

    property bool _busy: false
    property bool _cancelling: false
    property string _pendingPath: ""
    property string _lastPath: ""
    property string _lastError: ""
    property bool _lastCancelled: false

    function _dir() {
        return Config.get("screenshot.directory", "")
            || (Quickshell.env("HOME") + "/Pictures/Screenshots");
    }

    function _timestamp() {
        const d = new Date();
        const p = n => (n < 10 ? "0" : "") + n;
        return "" + d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate())
            + "-" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds());
    }

    function _start(useRegion) {
        if (root._busy)
            return "error: capture already in flight";
        const dir = root._dir();
        const path = dir + "/screenshot-" + root._timestamp() + ".png";
        root._busy = true;
        root._pendingPath = path;
        root._lastCancelled = false;
        if (useRegion) {
            // Palette guarantees #RRGGBB (palette.js HEX_RE), so appending an
            // alpha byte yields slurp's #RRGGBBAA form.
            slurpProc.environment = ({
                FS_SLURP_BG: Theme.color.background + "99",
                FS_SLURP_BORDER: Theme.color.accent + "FF",
                FS_SLURP_SEL: "#00000000",
                FS_SLURP_WEIGHT: "" + Theme.borderWidth
            });
            slurpProc.command = ["sh", "-c",
                'exec slurp -d -w "$FS_SLURP_WEIGHT" -b "$FS_SLURP_BG" -c "$FS_SLURP_BORDER" -s "$FS_SLURP_SEL"'];
            slurpProc.running = true;
            watchdog.interval = Config.get("screenshot.timeoutSeconds", 90) * 1000;
            watchdog.restart();
        } else {
            root._grab("");
        }
        return path;
    }

    // Paths and geometry ride the environment, not the script text, so a
    // screenshot.directory containing quotes or spaces can't splice the
    // shell command.
    function _grab(geometry) {
        captureProc.environment = ({
            FS_SHOT_DIR: root._dir(),
            FS_SHOT_PATH: root._pendingPath,
            FS_SHOT_GEOM: geometry
        });
        const grab = geometry !== ""
            ? 'grim -g "$FS_SHOT_GEOM" "$FS_SHOT_PATH"'
            : 'grim "$FS_SHOT_PATH"';
        captureProc.command = ["sh", "-c",
            'mkdir -p "$FS_SHOT_DIR" && ' + grab + ' && wl-copy --type image/png < "$FS_SHOT_PATH"'];
        captureProc.running = true;
    }

    function _cancel(reason) {
        if (!root._busy)
            return "error: no capture in flight";
        watchdog.stop();
        // _cancelling makes the killed process's own onExited a no-op so its
        // SIGTERM exit code can't repaint the state cleared here as an error.
        root._cancelling = slurpProc.running || captureProc.running;
        slurpProc.running = false;
        captureProc.running = false;
        root._busy = false;
        root._pendingPath = "";
        root._lastError = "";
        root._lastCancelled = true;
        NotificationService.notify("SCREENSHOT CANCELLED", reason);
        return "ok";
    }

    IpcHandler {
        target: "screenshot"

        function full(): string {
            return root._start(false);
        }

        function region(): string {
            return root._start(true);
        }

        function cancel(): string {
            return root._cancel("cancelled on demand");
        }

        function status(): string {
            return JSON.stringify({
                capturing: root._busy,
                lastPath: root._lastPath,
                lastError: root._lastError,
                lastCancelled: root._lastCancelled
            });
        }
    }

    // Region captures only: full() is one grim exec, but region() blocks on
    // a human answering slurp, which is exactly the state that sat stuck on
    // the host.
    Timer {
        id: watchdog
        onTriggered: root._cancel("no selection after " + Math.round(interval / 1000) + "s")
    }

    Process {
        id: slurpProc

        stdout: StdioCollector {
            id: slurpOut
        }
        stderr: StdioCollector {
            id: slurpErr
        }
        onExited: exitCode => {
            if (root._cancelling) {
                root._cancelling = false;
                return;
            }
            watchdog.stop();
            const geometry = slurpOut.text.trim();
            if (exitCode === 0 && geometry !== "") {
                root._grab(geometry);
                return;
            }
            root._busy = false;
            root._pendingPath = "";
            if (exitCode === 1) {
                // Escape/right-click inside slurp: the user declined the
                // selection themselves, so no toast and no lastError.
                root._lastError = "";
                root._lastCancelled = true;
                return;
            }
            root._lastError = slurpErr.text.trim()
                || (exitCode === 0 ? "slurp reported no geometry" : "slurp exited " + exitCode);
            console.warn("ScreenshotIpc:", root._lastError);
            NotificationService.notify("SCREENSHOT FAILED", root._lastError);
        }
    }

    Process {
        id: captureProc

        stderr: StdioCollector {
            id: captureStderr
        }
        onExited: exitCode => {
            if (root._cancelling) {
                root._cancelling = false;
                return;
            }
            watchdog.stop();
            root._busy = false;
            if (exitCode === 0) {
                root._lastPath = root._pendingPath;
                root._lastError = "";
                NotificationService.notify("SCREENSHOT SAVED", root._pendingPath);
                return;
            }
            root._lastError = captureStderr.text.trim() || ("capture exited " + exitCode);
            console.warn("ScreenshotIpc:", root._lastError);
            NotificationService.notify("SCREENSHOT FAILED", root._lastError);
        }
    }
}

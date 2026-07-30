import Quickshell
import Quickshell.Io

import qs.Core
import qs.Notifications

// `qs ipc call screenshot full|region|status` (M12 Task 9): grim writes
// <screenshot.directory>/screenshot-<timestamp>.png (slurp supplies the
// geometry for `region`), wl-copy puts the same PNG on the clipboard, and a
// SCREENSHOT SAVED notification fires through the shell's own
// NotificationService so there is visible feedback without any bar surface.
// IpcHandler replies are synchronous QMetaMethod invocations (quickshell
// src/io/ipchandler.cpp) and slurp blocks on user interaction indefinitely,
// so full()/region() reply with the destination path the capture is writing
// toward; a runtime failure (slurp cancelled, grim error) lands in a
// SCREENSHOT FAILED notification, a console.warn, and status()'s lastError:
// loud and queryable, never a silent no-op. Scope root, not a bare
// IpcHandler: IpcHandler has no default property, so the capture Process
// can't live inside it.
Scope {
    id: root

    property bool _busy: false
    property string _pendingPath: ""
    property string _lastPath: ""
    property string _lastError: ""

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
        // Paths ride the environment, not the script text, so a
        // screenshot.directory containing quotes or spaces can't splice the
        // shell command.
        captureProc.environment = ({ FS_SHOT_DIR: dir, FS_SHOT_PATH: path });
        const grab = useRegion
            ? 'g="$(slurp)" && grim -g "$g" "$FS_SHOT_PATH"'
            : 'grim "$FS_SHOT_PATH"';
        captureProc.command = ["sh", "-c",
            'mkdir -p "$FS_SHOT_DIR" && ' + grab + ' && wl-copy --type image/png < "$FS_SHOT_PATH"'];
        captureProc.running = true;
        return path;
    }

    IpcHandler {
        target: "screenshot"

        function full(): string {
            return root._start(false);
        }

        function region(): string {
            return root._start(true);
        }

        function status(): string {
            return JSON.stringify({
                capturing: root._busy,
                lastPath: root._lastPath,
                lastError: root._lastError
            });
        }
    }

    Process {
        id: captureProc

        stderr: StdioCollector {
            id: captureStderr
        }
        onExited: exitCode => {
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

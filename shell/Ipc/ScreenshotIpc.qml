import Quickshell
import Quickshell.Io
import QtQuick

import qs.Core
import qs.Notifications
import qs.Services

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
//
// Three routes, and only one of them is the rich one. `full()` and
// `region()` are non-interactive legacy paths (whole output, bare slurp)
// with no toolbar and no recording — they exist for anyone who wants a
// plain instant capture. `pick()` opens RegionPicker below, which is the
// only route carrying the toolbar, keyboard window selection, and
// recording; bind it to whatever chord is meant to be "the" screenshot
// bind. A compositor bind pointed at `region` where `pick smart default`
// was intended looks identical from the outside (both pop a selection
// overlay) and was exactly the misbinding that shipped unnoticed for
// weeks (M27).
Scope {
    id: root

    // The RegionPicker instance, set from shell.qml.
    property var picker: null

    property bool _busy: false
    property bool _cancelling: false
    property string _pendingPath: ""
    property string _lastPath: ""
    property string _lastError: ""
    property bool _lastCancelled: false

    // "default" saves to disk AND clipboard then offers the editor;
    // "copy" is clipboard only; "save" is disk only and skips the editor.
    // Upstream's `slurp|copy|save` third argument, renamed: "slurp" named the
    // picker it used, and this picker is not slurp.
    property string _processing: "default"

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
            // 0</dev/null is load-bearing: slurp reads stdin to EOF before
            // connecting to the compositor whenever stdin is not a tty (its
            // predefined-boxes feature), and quickshell's Process hands it a
            // pipe that never closes — slurp then blocks forever with zero
            // wayland fds and no surface (diagnosed live on the e1504g,
            // 2026-08-03; this was M13's "slurp sat invisible" mystery too).
            slurpProc.command = ["sh", "-c",
                'exec slurp -d -w "$FS_SLURP_WEIGHT" -b "$FS_SLURP_BG" -c "$FS_SLURP_BORDER" -s "$FS_SLURP_SEL" 0</dev/null'];
            slurpProc.running = true;
            watchdog.interval = Config.get("screenshot.timeoutSeconds", 90) * 1000;
            watchdog.restart();
        } else {
            root._grab("");
        }
        return path;
    }

    // Opens the region picker (M22 Task 5). `mode` is upstream's
    // smart|region|windows|fullscreen; `processing` is default|copy|save.
    function _pick(mode, processing) {
        if (root._busy)
            return "error: capture already in flight";
        if (!root.picker)
            return "error: picker not ready";
        root._busy = true;
        root._processing = processing || "default";
        root._pendingPath = root._dir() + "/screenshot-" + root._timestamp() + ".png";
        root._lastCancelled = false;
        const answer = root.picker.open(mode);
        if (answer !== "ok") {
            root._busy = false;
            return answer;
        }
        // The picker blocks on a human exactly as slurp did, so it inherits
        // the same watchdog rather than being trusted to always be answered.
        watchdog.interval = Config.get("screenshot.timeoutSeconds", 90) * 1000;
        watchdog.restart();
        return root._pendingPath;
    }

    Connections {
        target: root.picker

        // The picker is still mapped here, showing its frozen frames with the
        // chrome hidden, so grim photographs the freeze rather than live
        // content. picker.done() tears it down once grim has exited.
        function onPicked(rect) {
            watchdog.stop();
            root._grab(Math.round(rect.x) + "," + Math.round(rect.y) + " "
                + Math.round(rect.width) + "x" + Math.round(rect.height));
        }

        // niri crops server-side from the window's own buffer, so no rect and
        // no freeze is involved (see RegionPicker.qml's header for why a tiled
        // niri window has no rect to crop to in the first place). niri also
        // puts the PNG on the clipboard itself, which is why this path never
        // runs wl-copy.
        function onPickedWindow(windowId) {
            watchdog.stop();
            root._grabNiriWindow(windowId);
        }

        // The picker's toolbar can turn a pick into a recording, so this
        // target sees an outcome it takes no screenshot for. It handles it
        // anyway rather than giving the picker a second driver: one
        // full-screen surface with two owners is how it ends up opened twice,
        // or torn down by one while the other still thinks it is up. Nothing
        // of the recording itself lives here — RecordingService owns the path,
        // the audio, the notification and the child.
        //
        // The surface is already unmapped by the time this fires (wf-recorder
        // records live content, so the overlay had to be gone first);
        // picker.done() only settles the state it left behind.
        function onPickedRecord(rect, outputName) {
            watchdog.stop();
            root._busy = false;
            root._pendingPath = "";
            root._lastError = "";
            if (root.picker)
                root.picker.done();
            const answer = RecordingService.startAt({
                geometry: Math.round(rect.x) + "," + Math.round(rect.y) + " "
                    + Math.round(rect.width) + "x" + Math.round(rect.height),
                output: outputName,
                scope: "region",
                audio: Config.get("recording.audio", "none")
            });
            if (answer.indexOf("error:") !== 0)
                return;
            root._lastError = answer;
            console.warn("ScreenshotIpc:", answer);
            NotificationService.notify("RECORDING FAILED", answer);
        }

        function onCancelled(reason) {
            if (!root._busy)
                return;
            watchdog.stop();
            root._busy = false;
            root._pendingPath = "";
            root._lastCancelled = true;
            root._lastError = "";
        }
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
        // `copy` never touches the disk at all, so there is no file for the
        // editor action to open and none is offered.
        const pipeline = root._processing === "copy"
            ? grab.replace('"$FS_SHOT_PATH"', "-") + " | wl-copy --type image/png"
            : root._processing === "save"
                ? grab
                : grab + ' && wl-copy --type image/png < "$FS_SHOT_PATH"';
        captureProc.command = ["sh", "-c", 'mkdir -p "$FS_SHOT_DIR" && ' + pipeline];
        captureProc.running = true;
    }

    // `path` must be absolute or niri returns Err (niri-ipc v26.04
    // src/lib.rs:281). It always is here: _dir() is either an absolute
    // configured directory or $HOME/Pictures/Screenshots.
    function _grabNiriWindow(windowId) {
        captureProc.environment = ({
            FS_SHOT_DIR: root._dir(),
            FS_SHOT_PATH: root._pendingPath,
            FS_SHOT_WINDOW: windowId
        });
        captureProc.command = ["sh", "-c",
            'mkdir -p "$FS_SHOT_DIR" && exec niri msg action screenshot-window'
            + ' --id "$FS_SHOT_WINDOW" --write-to-disk true --path "$FS_SHOT_PATH"'];
        captureProc.running = true;
    }

    // Hands a captured PNG to the annotation editor. Default `tensaku-edit`
    // is the wrapper nix/tensaku-package.nix installs — Tensaku takes its
    // input as a flag rather than a positional argument, so the wrapper is
    // what accepts the "editor <path>" convention this calls with.
    //
    // The capture is already on disk and on the clipboard by the time this
    // runs, so a launch failure is its own warning and never repaints the
    // capture as failed.
    function edit(path) {
        if (!path)
            return "error: no path";
        editorProc.environment = ({
            FS_EDITOR: Config.get("screenshot.editor", "tensaku-edit"),
            FS_EDIT_PATH: path
        });
        editorProc.command = ["sh", "-c", 'exec "$FS_EDITOR" "$FS_EDIT_PATH"'];
        editorProc.running = true;
        return "ok";
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
        // Tear the overlay down directly rather than through picker.close():
        // that would fire onCancelled straight back into this function's own
        // state, and the picker must never outlive the capture it was opened
        // for — a full-screen surface left mapped is the worst failure here.
        if (root.picker && root.picker.isOpen)
            root.picker.done();
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

        // The picker (M22 Task 5). `mode` is smart|region|windows|fullscreen,
        // `processing` is default|copy|save — upstream's two positional
        // arguments, same names and same defaults.
        function pick(mode: string, processing: string): string {
            return root._pick(mode || "smart", processing || "default");
        }

        // Drives the picker's keyboard model headlessly for the smoke rig:
        // return | ctrl-return | tab | shift-tab | left | right | up | down |
        // escape. Real key handling is the feature; this is how it gets
        // verified without depending on synthetic key delivery into an
        // Exclusive-focus layer surface, the same split every other surface's
        // IPC actions already use.
        function key(name: string): string {
            if (!root.picker)
                return "error: picker not ready";
            return root.picker.key(name);
        }

        function pickerStatus(): string {
            if (!root.picker)
                return "error: picker not ready";
            return JSON.stringify(root.picker.status());
        }

        // Opens the last capture (or an explicit path) in the annotation
        // editor — the same thing the SAVED notification's EDIT action does,
        // reachable from a compositor keybind.
        function edit(path: string): string {
            return root.edit(path || root._lastPath);
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
        id: editorProc

        stderr: StdioCollector {
            id: editorStderr
        }
        onExited: exitCode => {
            if (exitCode === 0)
                return;
            const why = editorStderr.text.trim() || ("editor exited " + exitCode);
            console.warn("ScreenshotIpc: editor launch failed:", why);
            NotificationService.notify("EDITOR FAILED", why);
        }
    }

    Process {
        id: captureProc

        stderr: StdioCollector {
            id: captureStderr
        }
        onExited: exitCode => {
            // The picker is still mapped whenever it drove this capture: it
            // held the freeze up for grim, and only now has nothing left to
            // show. Torn down before any notification so the toast is not
            // hidden behind a full-screen overlay.
            if (root.picker && root.picker.isOpen)
                root.picker.done();

            if (root._cancelling) {
                root._cancelling = false;
                return;
            }
            watchdog.stop();
            root._busy = false;
            if (exitCode === 0) {
                root._lastError = "";

                // Clipboard-only: nothing landed on disk, so there is no path
                // to report, none to offer the editor, and no thumbnail.
                if (root._processing === "copy") {
                    root._lastPath = "";
                    NotificationService.notify("SCREENSHOT COPIED", "on the clipboard");
                    return;
                }

                root._lastPath = root._pendingPath;
                const saved = root._pendingPath;

                // `save` is the deliberately quiet mode: straight to disk, no
                // editor offered, matching upstream's own `save` processing.
                if (root._processing === "save") {
                    NotificationService.notify("SCREENSHOT SAVED", saved, 1, [], saved);
                    return;
                }
                // Key "default" rather than "edit": Toasts.qml and Center.qml
                // already route a click on the card body to the "default"
                // action, so one entry gets both the visible EDIT cell and
                // click-anywhere, without a second action nobody renders.
                NotificationService.notify("SCREENSHOT SAVED", saved, 1, [{
                    key: "default",
                    label: "EDIT",
                    invoke: () => root.edit(saved)
                }], saved);
                return;
            }
            root._lastError = captureStderr.text.trim() || ("capture exited " + exitCode);
            console.warn("ScreenshotIpc:", root._lastError);
            NotificationService.notify("SCREENSHOT FAILED", root._lastError);
        }
    }
}

import Quickshell
import Quickshell.Io
import QtQuick

import qs.Core
import qs.Notifications
import "../Capture/model.js" as Capture

// `qs ipc call capture text|color|cancel|status` (M22) is the third leg of
// the capture family, and deliberately its own target rather than more
// verbs on `screenshot`:
//
//   screenshot  saves a PNG to disk (and puts it on the clipboard).
//   capture     pulls something off the screen into the clipboard and
//               keeps no file: recognized text, or one pixel's color.
//   record      owns video.
//
// Both verbs here start with slurp and end with wl-copy, and both are
// guarded by one `_busy` flag plus one watchdog, so the two can never race
// each other for the pointer. Nothing coordinates this target with
// `screenshot`'s own slurp, though: firing `screenshot region` and `capture
// text` at the same time puts two slurp overlays on screen at once, and the
// second one gets the click.
//
// Color picking is a grim/coreutils pipeline, not a compositor call.
// Hyprland has no pick-colour request of its own to use instead, and
// `grim -t ppm`'s P6 output needs no image library to read (see
// Capture.hexFromPpmBytes for the byte layout).
//
// Scope root, not a bare IpcHandler: IpcHandler has no default property, so
// the pipeline Processes can't live inside it.
Scope {
    id: root

    property bool _busy: false
    property bool _cancelling: false
    // "text" | "color": which pipeline the pending slurp answer feeds.
    property string _mode: ""
    property string _lastHex: ""
    property string _lastText: ""
    property string _lastError: ""
    property bool _lastCancelled: false

    readonly property string _runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/formalshell"

    // `geometry` skips slurp and feeds the pipeline directly. It exists for
    // the same reason `picker choose` and `tray expand` do: both verbs here
    // otherwise begin with a human dragging a real pointer, which the smoke
    // rig has no way to synthesise, and slurp cannot be shimmed aside
    // because nix/package.nix installs it with makeWrapper's --prefix. Every
    // stage after the selection is the same code either way, so driving this
    // proves the OCR and pixel pipelines end to end.
    function _start(mode, geometry) {
        if (root._busy)
            return "error: capture already in flight";
        root._busy = true;
        root._mode = mode;
        root._lastCancelled = false;
        root._lastError = "";

        if (geometry) {
            if (mode === "color")
                root._runPick(geometry);
            else
                root._runOcr(geometry);
            return "ok";
        }

        // Colors resolve at call time so they follow matugen, exactly as
        // ScreenshotIpc's own region overlay does. Palette guarantees
        // #RRGGBB, so appending an alpha byte yields slurp's #RRGGBBAA.
        slurpProc.environment = ({
            FS_SLURP_BG: Theme.color.background + "99",
            FS_SLURP_BORDER: Theme.color.primary + "FF",
            FS_SLURP_SEL: "#00000000",
            FS_SLURP_WEIGHT: "" + Theme.borderWidth
        });
        if (mode === "color") {
            // No 0</dev/null here, and its absence is deliberate rather
            // than an oversight: slurp only drains stdin for its
            // predefined-boxes feature, and main.c gates that read on
            // `!state.single_point`, so point mode never reads stdin at
            // all. No crosshair flag: slurp 1.5.0 accepts only
            // -h -d -b -c -s -B -F -w -f -o -p -r -a, and an unknown option
            // makes it exit 1, which _onSlurpExited reads as the user
            // cancelling. Point mode draws its own cursor.
            slurpProc.command = ["sh", "-c",
                'exec slurp -p -w "$FS_SLURP_WEIGHT" -b "$FS_SLURP_BG" -c "$FS_SLURP_BORDER"'];
        } else {
            slurpProc.command = ["sh", "-c",
                'exec slurp -d -w "$FS_SLURP_WEIGHT" -b "$FS_SLURP_BG" -c "$FS_SLURP_BORDER" -s "$FS_SLURP_SEL" 0</dev/null'];
        }
        slurpProc.running = true;
        watchdog.interval = Config.get("capture.timeoutSeconds", 90) * 1000;
        watchdog.restart();
        return "ok";
    }

    // Paths and geometry ride the environment, never the script text, so a
    // runtime directory carrying quotes or spaces can't splice the command.
    // grim writes a real PNG rather than piping into tesseract: a pipeline's
    // status is its LAST command's, so a failed grim would otherwise arrive
    // as "no text found" instead of a failure.
    function _runOcr(geometry) {
        const base = root._runtimeDir + "/ocr";
        ocrProc.environment = ({
            FS_TMP_DIR: root._runtimeDir,
            FS_OCR_GEOM: geometry,
            FS_OCR_PNG: base + ".png",
            FS_OCR_BASE: base,
            FS_OCR_TXT: base + ".out",
            FS_OCR_LANG: Config.get("capture.ocrLanguage", "eng")
        });
        ocrProc.command = ["sh", "-c",
            'mkdir -p "$FS_TMP_DIR" || exit 2\n' +
            'grim -g "$FS_OCR_GEOM" "$FS_OCR_PNG" || exit 2\n' +
            'tesseract "$FS_OCR_PNG" "$FS_OCR_BASE" --oem 1 --psm 6 -l "$FS_OCR_LANG" --dpi 300 -c preserve_interword_spaces=1 || exit 2\n' +
            // tesseract ends every page with a form feed.
            'tr -d "\\f" < "$FS_OCR_BASE.txt" > "$FS_OCR_TXT" || exit 2\n' +
            'rm -f "$FS_OCR_PNG" "$FS_OCR_BASE.txt"\n' +
            '[ -n "$(tr -d "[:space:]" < "$FS_OCR_TXT")" ] || exit 3\n' +
            'wl-copy --type text/plain < "$FS_OCR_TXT" || exit 2\n' +
            'cat "$FS_OCR_TXT"\n'];
        ocrProc.running = true;
    }

    function _runPick(geometry) {
        pickProc.environment = ({
            FS_TMP_DIR: root._runtimeDir,
            FS_PICK_GEOM: geometry,
            FS_PICK_PPM: root._runtimeDir + "/pick.ppm"
        });
        pickProc.command = ["sh", "-c",
            'mkdir -p "$FS_TMP_DIR" || exit 2\n' +
            'grim -g "$FS_PICK_GEOM" -t ppm "$FS_PICK_PPM" || exit 2\n' +
            'out=$(tail -c 3 "$FS_PICK_PPM" | od -An -tu1) || exit 2\n' +
            'rm -f "$FS_PICK_PPM"\n' +
            'printf \'%s\' "$out"\n'];
        pickProc.running = true;
    }

    function _cancel(reason) {
        if (!root._busy)
            return "error: no capture in flight";
        watchdog.stop();
        // _cancelling makes the killed process's own onExited a no-op, so
        // its SIGTERM exit code can't repaint the state cleared here as an
        // error.
        root._cancelling = slurpProc.running || ocrProc.running || pickProc.running;
        slurpProc.running = false;
        ocrProc.running = false;
        pickProc.running = false;
        root._busy = false;
        root._mode = "";
        root._lastError = "";
        root._lastCancelled = true;
        NotificationService.notify("CAPTURE CANCELLED", reason);
        return "ok";
    }

    function _fail(why) {
        root._busy = false;
        root._mode = "";
        root._lastError = why;
        console.warn("CaptureIpc:", why);
        NotificationService.notify("CAPTURE FAILED", why);
    }

    IpcHandler {
        target: "capture"

        // Select a region, run OCR over it, put the recognized text on the
        // clipboard.
        function text(): string {
            return root._start("text", "");
        }

        // Pick one pixel, put its #RRGGBB on the clipboard.
        function color(): string {
            return root._start("color", "");
        }

        // Same two pipelines against a geometry the caller already has
        // ("X,Y WxH"), skipping the selection. Separate verbs rather than an
        // optional argument: IpcHandler dispatches on exact arity, so a
        // defaulted parameter would break the bare `capture text` a keybind
        // actually calls. colorAt reads the geometry's top-left pixel.
        function textAt(geometry: string): string {
            return root._start("text", geometry);
        }

        function colorAt(geometry: string): string {
            return root._start("color", geometry);
        }

        function cancel(): string {
            return root._cancel("cancelled on demand");
        }

        function status(): string {
            return JSON.stringify({
                capturing: root._busy,
                mode: root._mode,
                lastHex: root._lastHex,
                lastText: root._lastText,
                lastError: root._lastError,
                lastCancelled: root._lastCancelled
            });
        }
    }

    // Both verbs block on a human answering slurp, which is exactly the
    // state that once sat stuck for over an hour on the e1504g.
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
            const geometry = Capture.parseGeometry(slurpOut.text);
            if (exitCode === 0 && geometry !== "") {
                if (root._mode === "color")
                    root._runPick(geometry);
                else
                    root._runOcr(geometry);
                return;
            }
            if (exitCode === 1) {
                // Escape/right-click inside slurp: the user declined the
                // selection themselves, so no toast and no lastError.
                root._busy = false;
                root._mode = "";
                root._lastCancelled = true;
                return;
            }
            root._fail(slurpErr.text.trim()
                || (exitCode === 0 ? "slurp reported no geometry" : "slurp exited " + exitCode));
        }
    }

    Process {
        id: ocrProc

        stdout: StdioCollector {
            id: ocrOut
        }
        stderr: StdioCollector {
            id: ocrErr
        }
        onExited: exitCode => {
            if (root._cancelling) {
                root._cancelling = false;
                return;
            }
            const outcome = Capture.ocrOutcome(exitCode);
            if (outcome === "ok") {
                root._busy = false;
                root._mode = "";
                root._lastText = ocrOut.text.trim();
                root._lastError = "";
                NotificationService.notify("TEXT COPIED", root._lastText);
                return;
            }
            if (outcome === "empty") {
                // A real answer, not a failure: nothing was copied and
                // there is nothing to warn about.
                root._busy = false;
                root._mode = "";
                root._lastText = "";
                root._lastError = "";
                NotificationService.notify("NO TEXT FOUND", "the selected region held no readable text");
                return;
            }
            root._fail(ocrErr.text.trim() || ("ocr exited " + exitCode));
        }
    }

    Process {
        id: pickProc

        stdout: StdioCollector {
            id: pickOut
        }
        stderr: StdioCollector {
            id: pickErr
        }
        onExited: exitCode => {
            if (root._cancelling) {
                root._cancelling = false;
                return;
            }
            const hex = exitCode === 0 ? Capture.hexFromPpmBytes(pickOut.text) : "";
            if (hex === "") {
                root._fail(pickErr.text.trim() || ("could not read the pixel (grim exited " + exitCode + ")"));
                return;
            }
            root._busy = false;
            root._mode = "";
            root._lastHex = hex;
            root._lastError = "";
            copyProc.environment = ({ FS_PICK_HEX: hex });
            copyProc.command = ["sh", "-c", 'printf \'%s\' "$FS_PICK_HEX" | wl-copy --type text/plain'];
            copyProc.running = true;
        }
    }

    Process {
        id: copyProc

        stderr: StdioCollector {
            id: copyErr
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root._fail(copyErr.text.trim() || ("wl-copy exited " + exitCode));
                return;
            }
            NotificationService.notify("COLOR COPIED", root._lastHex);
        }
    }
}

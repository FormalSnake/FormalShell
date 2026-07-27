pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// `qs.Core as Core`, not a bare import: QtQuick already exports a type
// named State (for property-binding states), and an unqualified `import
// qs.Core` loses that name collision — State.wallpaper reads back
// undefined at runtime instead of hitting the qs.Core singleton (verified
// with a throwaway probe script). Core.State disambiguates it.
import qs.Core as Core
import qs.Compositor
import "matugen.js" as Matugen
import "palette.js" as Palette

// Serializes matugen runs behind a running/pending queue: retheme() during a
// run just sets pending, the run in flight is never killed mid-write, and a
// run that ends with pending set immediately reruns once. Reads the user's
// own matugen ecosystem (~/.config/matugen/config.toml, and drop-ins from
// ~/.config/formalshell/matugen.d/*.toml) with a single `cat` Process —
// Quickshell.Io has no directory-listing API — merges it via matugen.js's
// buildConfig(), writes matugen-merged.toml, then runs matugen against it.
// matugen's own template output_paths land on <state-dir>/{theme.json,
// niri-border.kdl}.tmp; on success those are renamed into place atomically
// and the niri border fragment is reapplied. No wallpaper set → skip matugen
// entirely and write palette.fallback() so theme.json always exists in the
// same shape. theme.json's own FileView drives the "run once if absent"
// startup behavior declaratively.
//
// Every write (merged config, fallback theme.json) goes through a Process
// (`printf '%s' "$content" > "$path"`, content passed as its own argv entry
// so no shell-quoting is needed), never FileView.setText(): FileView skips
// the write AND the saved() signal entirely when the new text is byte-
// identical to what's already on disk (fileview.cpp's writeCmpData() check)
// — a real hazard here, since two retheme() runs back to back for the same
// wallpaper/mode produce byte-identical output, and gating the pipeline on
// saved() would wedge running=true forever on the second run. Verified by
// reproducing the wedge with a throwaway probe script before switching to
// Process-based writes.
//
// --prefer is required, not cosmetic: matugen prompts on an ambiguous source
// color, but Process gives it no TTY/stdin to prompt on, so an unprefixed run
// against a near-solid wallpaper — a very plausible choice for this shell's
// brutalist aesthetic — fails outright with "no preference was inputted, and
// a terminal was not detected" (verified against a solid-swatch PNG).
// --prefer=darkness/lightness, matched to State.mode, resolves it
// deterministically without needing a --fallback-color.
Singleton {
    id: root

    readonly property string stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/formalshell";
    }
    readonly property string _templateDir: Quickshell.shellPath("Theme/templates")
    readonly property string _userConfigPath: (Quickshell.env("HOME") || "") + "/.config/matugen/config.toml"
    readonly property string _dropInDir: (Quickshell.env("HOME") || "") + "/.config/formalshell/matugen.d"
    readonly property string _mergedConfigPath: root.stateDir + "/matugen-merged.toml"
    readonly property string _themeJsonPath: root.stateDir + "/theme.json"
    readonly property string _borderKdlPath: root.stateDir + "/niri-border.kdl"
    readonly property string _dropInBoundary: "#--formalshell-dropin-boundary--"

    property bool running: false
    property bool pending: false

    function retheme() {
        if (root.running) {
            root.pending = true;
            return;
        }
        root.running = true;
        root._start();
    }

    function _finish() {
        root.running = false;
        if (root.pending) {
            root.pending = false;
            root.retheme();
        }
    }

    function _writeFile(path, content, onDone) {
        var proc = writeFileProcComponent.createObject(root, {
            _onDone: onDone
        });
        proc.command = ["sh", "-c", 'printf \'%s\' "$2" > "$1"', "sh", path, content];
        proc.running = true;
    }

    Component {
        id: writeFileProcComponent

        Process {
            property var _onDone
            onExited: exitCode => {
                var cb = _onDone;
                destroy();
                cb(exitCode);
            }
        }
    }

    function _start() {
        if (Core.State.wallpaper === "") {
            root._writeFile(root._themeJsonPath, JSON.stringify(Palette.fallback(), null, 2), exitCode => {
                if (exitCode !== 0)
                    console.warn("ThemeEngine: failed to write fallback theme.json, code", exitCode);
                root._finish();
            });
            return;
        }
        readConfigsProc.command = ["sh", "-c",
            'cat "$1" 2>/dev/null; echo "$3"; for f in "$2"/*.toml; do [ -f "$f" ] && cat "$f" && echo; done',
            "sh", root._userConfigPath, root._dropInDir, root._dropInBoundary];
        readConfigsProc.running = true;
    }

    Process {
        id: readConfigsProc

        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.split(root._dropInBoundary);
                var userConfigText = parts[0] || null;
                var dropInsText = (parts[1] || "").trim();
                var cfg = Matugen.buildConfig({
                    shellTemplateDir: root._templateDir,
                    stateDir: root.stateDir,
                    userConfigText: userConfigText,
                    dropInTexts: dropInsText ? [dropInsText] : []
                });
                root._writeFile(root._mergedConfigPath, cfg, exitCode => {
                    if (exitCode !== 0) {
                        console.warn("ThemeEngine: failed to write matugen-merged.toml, code", exitCode);
                        root._finish();
                        return;
                    }
                    matugenProc.command = ["matugen", "image", Core.State.wallpaper, "-m", Core.State.mode,
                        "-c", root._mergedConfigPath,
                        "--prefer", Core.State.mode === "light" ? "lightness" : "darkness"];
                    matugenProc.running = true;
                });
            }
        }
    }

    Process {
        id: matugenProc

        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("ThemeEngine: matugen exited with code", exitCode);
                root._finish();
                return;
            }
            renameProc.command = ["sh", "-c", 'mv -f "$1" "$2" && mv -f "$3" "$4"',
                "sh",
                root.stateDir + "/theme.json.tmp", root._themeJsonPath,
                root.stateDir + "/niri-border.kdl.tmp", root._borderKdlPath];
            renameProc.running = true;
        }
    }

    Process {
        id: renameProc

        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("ThemeEngine: failed to publish theme.json/niri-border.kdl, code", exitCode);
                root._finish();
                return;
            }
            // applyThemeFragment() lands on CompositorService in Task 6; guard so a
            // retheme() before then can't throw mid-handler and wedge running=true.
            if (typeof CompositorService.applyThemeFragment === "function")
                CompositorService.applyThemeFragment();
            root._finish();
        }
    }

    // Startup probe only — reads theme.json once to detect a first run;
    // writes never go through here (see the FileView.setText() hazard above).
    FileView {
        id: themeProbe
        path: root._themeJsonPath

        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root.retheme();
        }
    }

    Connections {
        target: Core.State
        function onWallpaperChanged() { root.retheme(); }
        function onModeChanged() { root.retheme(); }
    }
}

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
// entirely and write palette.fallback(State.mode) — the Flexoki variant for
// the current mode, so `theme mode toggle` recolors every consumer live
// through the exact same theme.json write a matugen run uses (M13b Task 3;
// before that the fallback was static dark and toggling without a wallpaper
// visibly did nothing). theme.json's own FileView drives the "run once if
// absent" startup behavior declaratively; State.mode defaults to dark, so
// the seeded first-boot theme.json stays the dark variant.
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
// The source color is pinned to matugen's own rank 0, not left to --prefer.
//
// Some source-color decision has to be forced: matugen prompts when an image
// yields more than one candidate, and Process gives it no TTY/stdin to prompt
// on, so an unforced run fails outright with "no preference was inputted, and
// a terminal was not detected" (verified against a solid-swatch PNG). It is
// also the common case, not an edge one: 50 of the owner's 57 wallpapers on
// g815 produce multiple candidates.
//
// Every --prefer value is a scalar tiebreak over those candidates (the
// lightest, the most saturated, ...) and none of them asks what the wallpaper
// actually looks like. `lightness` reads a small warm highlight as the
// image's color: measured across those 57 wallpapers (2026-08-14) its pick
// sat a mean 50 degrees of hue away from the image's own saturation-weighted
// dominant hue, 20 of them more than 45 degrees off. A blue tower shot seeds
// a tan scheme under it, a navy interior seeds gold.
//
// matugen already ranks candidates by material's own Score and prints that
// ranking under -d, and rank 0 is the image's color by material's reckoning
// (mean 14 degrees off, 5 outliers, over the same corpus). So a retheme runs
// matugen twice: a --dry-run probe reads the ranking off stderr, then the
// real run pins the source to rank 0 with `--prefer closest-to-fallback
// --fallback-color <rank0>`, which resolves to that exact candidate since its
// distance to itself is zero. The real run stays `matugen image`, so a user
// template reading image-derived variables still gets them. A probe that
// finds no ranking falls back to `--prefer saturation` (the least-bad scalar
// on the same corpus: mean 42 degrees, 15 outliers) and warns.
//
// Whichever path runs, the choice is a function of the wallpaper alone, never
// of State.mode: a mode-matched darkness/lightness pair used to flip the same
// wallpaper's hue family across a mode toggle (verified 2026-08-09 against a
// green-foliage wallpaper), while -m alone tones the scheme.
Singleton {
    id: root

    readonly property string stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/formalshell";
    }
    readonly property string _templateDir: Quickshell.shellPath("Theme/templates")
    readonly property string _homeDir: Quickshell.env("HOME") || ""
    readonly property string _userConfigPath: root._homeDir + "/.config/matugen/config.toml"
    readonly property string _dropInDir: (Quickshell.env("HOME") || "") + "/.config/formalshell/matugen.d"
    readonly property string _mergedConfigPath: root.stateDir + "/matugen-merged.toml"
    readonly property string _themeJsonPath: root.stateDir + "/theme.json"
    readonly property string _borderKdlPath: root.stateDir + "/niri-border.kdl"
    readonly property string _dropInBoundary: "#--formalshell-dropin-boundary--"

    property bool running: false
    property bool pending: false

    // Existence check for ThemeIpc's status(), tracked by hand rather than
    // via FileView.loaded + watchChanges: QFileSystemWatcher silently fails
    // to attach to a path (or its parent dir) that doesn't exist yet at
    // construction time — the common case for a fresh state dir — so it
    // never notices this singleton's own later out-of-band Process writes
    // (verified by reproducing the stuck-false read against a real run).
    // ThemeEngine is theme.json's only writer, so it can just say so itself.
    property bool themeJsonPresent: false

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

    // Ordinary apps never read theme.json: GTK4/libadwaita, GTK3 (≥3.24.30,
    // via the settings portal), browsers and Electron learn light/dark and
    // the GTK theme name from org.gnome.desktop.interface, which
    // xdg-desktop-portal-gtk re-broadcasts as org.freedesktop.appearance —
    // so every retheme must assert the runtime signal too, or Mod+Shift+T
    // recolors the shell while every app stays frozen in its old mode.
    // dconf, not gsettings: on NixOS glib schemas live under per-package
    // share/gsettings-schemas/ paths, so a bare `gsettings set` from the
    // shell's environment fails with "No schemas installed" (verified on the
    // e1504g); `dconf write` hits the same backend schema-free. Fire and
    // forget — the matugen pipeline must not gate on it.
    function _syncSystemScheme() {
        var dark = Core.State.mode !== "light";
        var proc = writeFileProcComponent.createObject(root, {
            _onDone: function (exitCode) {
                if (exitCode !== 0)
                    console.warn("ThemeEngine: dconf color-scheme sync failed, code", exitCode);
            }
        });
        proc.command = ["sh", "-c",
            'dconf write /org/gnome/desktop/interface/color-scheme "$1" && dconf write /org/gnome/desktop/interface/gtk-theme "$2"',
            "sh",
            dark ? "'prefer-dark'" : "'prefer-light'",
            dark ? "'adw-gtk3-dark'" : "'adw-gtk3'"];
        proc.running = true;
    }

    function _start() {
        root._syncSystemScheme();
        if (Core.State.wallpaper === "") {
            root._writeFile(root._themeJsonPath, JSON.stringify(Palette.fallback(Core.State.mode), null, 2), exitCode => {
                if (exitCode !== 0)
                    console.warn("ThemeEngine: failed to write fallback theme.json, code", exitCode);
                else
                    root.themeJsonPresent = true;
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
                    homeDir: root._homeDir,
                    userConfigText: userConfigText,
                    dropInTexts: dropInsText ? [dropInsText] : []
                });
                root._writeFile(root._mergedConfigPath, cfg, exitCode => {
                    if (exitCode !== 0) {
                        console.warn("ThemeEngine: failed to write matugen-merged.toml, code", exitCode);
                        root._finish();
                        return;
                    }
                    // Extraction only: --dry-run writes no template and runs
                    // no command, and -d is what prints the ranking. -q would
                    // silence that ranking, so it is deliberately absent.
                    sourceProbeProc.command = ["matugen", "-d", "image", Core.State.wallpaper, "--dry-run",
                        "--prefer", "saturation"];
                    sourceProbeProc.running = true;
                });
            }
        }
    }

    Process {
        id: sourceProbeProc

        stderr: StdioCollector {
            id: sourceProbeErr
        }

        onExited: exitCode => {
            var source = exitCode === 0 ? Matugen.rankedSourceColor(sourceProbeErr.text) : null;
            if (!source)
                console.warn("ThemeEngine: no source-color ranking from matugen (code", exitCode + "), falling back to --prefer saturation");
            var pick = source
                ? ["--prefer", "closest-to-fallback", "--fallback-color", source]
                : ["--prefer", "saturation"];
            matugenProc.command = ["matugen", "image", Core.State.wallpaper, "-m", Core.State.mode,
                "-c", root._mergedConfigPath].concat(pick);
            matugenProc.running = true;
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
            root.themeJsonPresent = true;
            CompositorService.applyThemeFragment();
            root._finish();
        }
    }

    // Startup probe only — reads theme.json once to detect a first run and
    // seed themeJsonPresent's initial value; writes never go through here
    // (see the FileView.setText() hazard above). Every later transition of
    // themeJsonPresent is set directly by the write sites above, not by
    // watching this file.
    FileView {
        id: themeProbe
        path: root._themeJsonPath

        onLoaded: root.themeJsonPresent = true
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.themeJsonPresent = false;
                root.retheme();
            }
        }
    }

    // Startup guarantee: a niri config's `include ".../niri-border.kdl"`
    // must never hit a missing file. retheme() only ever produces this path
    // via matugen's successful output, so a state dir that has never seen a
    // successful run (fresh install, or wallpaper never set) leaves it
    // absent — create it empty once, here, so the include is always safe.
    // Never rewrites existing content: retheme()'s atomic rename is the only
    // writer once matugen has actually run.
    FileView {
        id: borderProbe
        path: root._borderKdlPath

        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root._writeFile(root._borderKdlPath, "", function () {});
        }
    }

    Connections {
        target: Core.State
        function onWallpaperChanged() { root.retheme(); }
        function onModeChanged() { root.retheme(); }
    }
}

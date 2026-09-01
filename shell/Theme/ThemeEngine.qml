pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// `qs.Core as Core`, not a bare import: QtQuick already exports a type
// named State (for property-binding states), and an unqualified `import
// qs.Core` loses that name collision, State.wallpaper reads back
// undefined at runtime instead of hitting the qs.Core singleton (verified
// with a throwaway probe script). Core.State disambiguates it.
import qs.Core as Core
import "chrome.js" as Chrome
import "matugen.js" as Matugen
import "palette.js" as Palette

// Serializes matugen runs behind a running/pending queue: retheme() during a
// run just sets pending, the run in flight is never killed mid-write, and a
// run that ends with pending set immediately reruns once. Reads the user's
// own matugen ecosystem (~/.config/matugen/config.toml, and drop-ins from
// ~/.config/formalshell/matugen.d/*.toml) with a single `cat` Process,
// Quickshell.Io has no directory-listing API, merges it via matugen.js's
// buildConfig(), writes matugen-merged.toml, then runs matugen against it.
// matugen's own template output_paths land on <state-dir>/{theme.json,
// formalshell-colors.conf, formalshell-colors.lua}.tmp; on success those are
// renamed into place atomically, theme.json into the state dir and both
// Hyprland palettes (hyprlang for a hyprland.conf that sources it, a Lua
// table for a hyprland.lua that dofiles it) into the user's hypr config dir,
// followed by one `hyprctl reload`. No wallpaper set → skip matugen
// entirely and write palette.fallback(State.mode) — the zinc variant for
// the current mode, so `theme mode toggle` recolors every consumer live
// through the exact same theme.json write a matugen run uses (M13b Task 3;
// before that the fallback was static dark and toggling without a wallpaper
// visibly did nothing).
//
// A wallpaper whose path carries "flexoki" still runs matugen, but nothing
// on that run reads matugen's scheme: every template is rewritten first
// (matugen.js's substituteFlexoki, against flexoki.js's Material-role and
// base16 views) and matugen renders the rewritten copies out of
// <state-dir>/flexoki-templates, so the GTK/Qt palettes and every template
// the user declared land on real Flexoki tones rather than a Material scheme
// grown from one blue seed. The run itself is `color hex` on Flexoki blue
// rather than `image`, which only seeds the keywords no rewrite covers; the
// shell's own outputs of it are discarded and theme.json plus both Hyprland
// palettes take palette.flexoki(State.mode) through the static write.
// theme.json's own FileView drives the "run once if
// absent" startup behavior declaratively; State.mode defaults to dark, so
// the seeded first-boot theme.json stays the dark variant.
//
// Every write (merged config, fallback theme.json) goes through a Process
// (`printf '%s' "$content" > "$path"`, content passed as its own argv entry
// so no shell-quoting is needed), never FileView.setText(): FileView skips
// the write AND the saved() signal entirely when the new text is byte-
// identical to what's already on disk (fileview.cpp's writeCmpData() check)
//, a real hazard here, since two retheme() runs back to back for the same
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
    readonly property string _configDir: Quickshell.env("XDG_CONFIG_HOME") || (root._homeDir + "/.config")
    readonly property string _hyprColorsTmp: root.stateDir + "/formalshell-colors.conf.tmp"
    readonly property string _hyprColorsPath: root._configDir + "/hypr/formalshell-colors.conf"
    readonly property string _hyprColorsLuaTmp: root.stateDir + "/formalshell-colors.lua.tmp"
    readonly property string _hyprColorsLuaPath: root._configDir + "/hypr/formalshell-colors.lua"
    readonly property string _hyprChromePath: root._configDir + "/hypr/formalshell-chrome.conf"
    readonly property string _hyprChromeLuaPath: root._configDir + "/hypr/formalshell-chrome.lua"
    readonly property string _dropInBoundary: "#--formalshell-dropin-boundary--"
    readonly property string _templateBoundary: "#--formalshell-template-boundary--"
    readonly property string _chromeBoundary: "#--formalshell-chrome-boundary--"
    // Where a Flexoki-pinned run stages the rewritten copy of every template
    // it is about to hand matugen. Regenerated per run, never read back.
    readonly property string _flexokiDir: root.stateDir + "/flexoki-templates"

    property bool running: false
    property bool pending: false
    // Captured when the run's matugen command is built, not re-read at exit:
    // a wallpaper flip mid-run must not send this run's outputs down the
    // other publish path (the pending rerun covers the new wallpaper).
    property bool _pinnedRun: false
    // The pinned run's merged config between the template read and the write,
    // the input paths it was read from (positional, matching the config's own
    // order), and the expressions no Flexoki value answered.
    property string _pinnedConfig: ""
    property var _pinnedInputs: []
    property var _pinnedSkipped: []

    // Existence check for ThemeIpc's status(), tracked by hand rather than
    // via FileView.loaded + watchChanges: QFileSystemWatcher silently fails
    // to attach to a path (or its parent dir) that doesn't exist yet at
    // construction time, the common case for a fresh state dir, so it
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

    // quickshell's Process emits no `exited` when the command never starts
    // (NightLightService.qml's own learned idiom: onErrorOccurred only
    // emits runningChanged for FailedToStart). Every named Process in the
    // retheme pipeline is one step `_finish()` is reached through, so a
    // missing `matugen` or `sh` would otherwise latch `running` true
    // forever and leave every later retheme() call only setting `pending`
    // with nothing left to ever clear it.
    function _pipelineFailedToStart(bin) {
        console.warn("ThemeEngine:", bin, "not found (failed to start)");
        root._finish();
    }

    function _writeFile(path, content, onDone) {
        var proc = writeFileProcComponent.createObject(root, {
            _onDone: onDone
        });
        proc.command = ["sh", "-c", 'printf \'%s\' "$2" > "$1"', "sh", path, content];
        proc.running = true;
    }

    // The atomic twin of _writeFile, for a path another process reads out of
    // band: Hyprland re-reads a sourced file the moment it changes, and
    // dofiles the Lua one on the reload below, so neither can be caught half
    // written. Creates the parent directory too, since ~/.config/hypr need
    // not exist on a fresh install.
    function _publishFile(path, content, onDone) {
        var proc = writeFileProcComponent.createObject(root, {
            _onDone: onDone
        });
        proc.command = ["sh", "-c",
            'mkdir -p "$(dirname "$1")" && printf \'%s\' "$2" > "$1.tmp" && mv -f "$1.tmp" "$1"',
            "sh", path, content];
        proc.running = true;
    }

    // Both Hyprland palettes at once, for the no-wallpaper path: matugen
    // renders them from its own templates on a real run, but the fallback
    // has to write them itself or a hyprland config reading either one finds
    // nothing until the first wallpaper is set.
    function _publishHyprColors(palette, onDone) {
        root._publishFile(root._hyprColorsPath, Matugen.hyprlandColors(palette), confCode => {
            if (confCode !== 0)
                console.warn("ThemeEngine: failed to write fallback formalshell-colors.conf, code", confCode);
            root._publishFile(root._hyprColorsLuaPath, Matugen.hyprlandColorsLua(palette), luaCode => {
                if (luaCode !== 0)
                    console.warn("ThemeEngine: failed to write fallback formalshell-colors.lua, code", luaCode);
                onDone();
            });
        });
    }

    // The rounding and blur twin of _publishHyprColors, and the reason it sits
    // outside the matugen pipeline: both values come from settings.json, which
    // no matugen template can read, and neither has anything to do with the
    // wallpaper. Runs on startup as well as on change so a hyprland config
    // reading $rounding/$blur finds them from the shell's first run, the same
    // guarantee the colours file gives. Deliberately clear of running/pending:
    // _publishFile is atomic per file, so two overlapping writes of the same
    // content cannot tear, and queueing them behind a matugen run would only
    // delay a value that is already known.
    function _writeChromeFiles(confText, luaText, onDone) {
        root._publishFile(root._hyprChromePath, confText, confCode => {
            if (confCode !== 0)
                console.warn("ThemeEngine: failed to write formalshell-chrome.conf, code", confCode);
            root._publishFile(root._hyprChromeLuaPath, luaText, luaCode => {
                if (luaCode !== 0)
                    console.warn("ThemeEngine: failed to write formalshell-chrome.lua, code", luaCode);
                onDone();
            });
        });
    }

    // Hyprland re-reads a sourced hyprlang file the moment it changes, so an
    // unchanged startup still re-arranges every layer if this writes and
    // reloads unconditionally. Probes the two files on disk first (a `cat`,
    // empty when either is absent, which never equals real chrome text --
    // a fresh install still gets its first write, docs/DESIGN.md's "must
    // exist from first run") and skips both the write and the reload when
    // the rendered text already matches. A probe that can't say (failed to
    // start, or `text` null below) publishes unconditionally rather than
    // risk silently skipping a real change.
    function _publishHyprChrome(onDone) {
        var chrome = {
            rounding: Core.Theme.radius,
            blur: Core.Theme.blurBehind
        };
        var confText = Chrome.hyprlandChrome(chrome);
        var luaText = Chrome.hyprlandChromeLua(chrome);
        var probe = chromeProbeComponent.createObject(root, {
            _onResult: function (text) {
                if (text !== null) {
                    var parts = text.split(root._chromeBoundary);
                    if ((parts[0] || "") === confText && (parts[1] || "") === luaText) {
                        onDone();
                        return;
                    }
                }
                root._writeChromeFiles(confText, luaText, onDone);
            }
        });
        probe.command = ["sh", "-c",
            'cat "$1" 2>/dev/null; printf \'%s\' "$3"; cat "$2" 2>/dev/null',
            "sh", root._hyprChromePath, root._hyprChromeLuaPath, root._chromeBoundary];
        probe.running = true;
    }

    // Ephemeral per call, the same reason writeFileProcComponent is: two
    // publishes racing (radius and blur landing in the same tick) must not
    // share one Process and drop a callback.
    Component {
        id: chromeProbeComponent

        Process {
            id: chromeProbeProc
            property var _onResult
            property bool _sawExit: false

            stdout: StdioCollector {
                id: chromeProbeOut
                onStreamFinished: {
                    chromeProbeProc._sawExit = true;
                    var cb = chromeProbeProc._onResult;
                    chromeProbeProc.destroy();
                    cb(chromeProbeOut.text);
                }
            }
            onRunningChanged: {
                if (chromeProbeProc.running || chromeProbeProc._sawExit)
                    return;
                var cb = chromeProbeProc._onResult;
                chromeProbeProc.destroy();
                cb(null);
            }
        }
    }

    // Hyprland re-reads a hyprlang file it sourced itself the moment it
    // changes, so formalshell-colors.conf needs no call. Hyprland 0.55's Lua
    // config cannot source hyprlang and reads formalshell-colors.lua with
    // dofile instead, which is not a sourced file and gets no re-read, so
    // that half has to be asked for. Guarded on the env var for the same
    // reason HyprlandBackend.refreshOutputs() is: this singleton runs under
    // niri too. One call per publish: retheme() queues rather than
    // overlapping, so a run in flight can never land a second one here.
    function _reloadHyprland() {
        if (!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || reloadProc.running)
            return;
        reloadProc.running = true;
    }

    Process {
        id: reloadProc
        command: ["hyprctl", "reload"]
        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("ThemeEngine: hyprctl reload exited with code", exitCode);
        }
    }

    Component {
        id: writeFileProcComponent

        Process {
            id: writeFileProc
            property var _onDone
            property bool _sawExit: false
            // A missing `sh` synthesizes the same nonzero-exit-code shape
            // every _onDone callback already handles (warn and carry on),
            // so no call site needs its own FailedToStart branch.
            onRunningChanged: {
                if (writeFileProc.running || writeFileProc._sawExit)
                    return;
                var cb = _onDone;
                destroy();
                cb(-1);
            }
            onExited: exitCode => {
                writeFileProc._sawExit = true;
                var cb = _onDone;
                destroy();
                cb(exitCode);
            }
        }
    }

    // Ordinary apps never read theme.json: GTK4/libadwaita, GTK3 (≥3.24.30,
    // via the settings portal), browsers and Electron learn light/dark and
    // the GTK theme name from org.gnome.desktop.interface, which
    // xdg-desktop-portal-gtk re-broadcasts as org.freedesktop.appearance,
    // so every retheme must assert the runtime signal too, or Mod+Shift+T
    // recolors the shell while every app stays frozen in its old mode.
    // dconf, not gsettings: on NixOS glib schemas live under per-package
    // share/gsettings-schemas/ paths, so a bare `gsettings set` from the
    // shell's environment fails with "No schemas installed" (verified on the
    // e1504g); `dconf write` hits the same backend schema-free. Fire and
    // forget, the matugen pipeline must not gate on it.
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

    // The static write the no-wallpaper zinc path and a Flexoki pin both end
    // on: theme.json straight from the palette object, then both Hyprland
    // colours files, then one reload. Goes through _publishFile rather than
    // _writeFile: Core/Theme.qml watches theme.json directly, and _writeFile
    // truncates before writing, so a reload catching that window would flip
    // the shell to the fallback palette (the matugen path already renames
    // atomically for the same reason).
    function _publishStatic(palette) {
        root._publishFile(root._themeJsonPath, JSON.stringify(palette, null, 2), exitCode => {
            if (exitCode !== 0)
                console.warn("ThemeEngine: failed to write static theme.json, code", exitCode);
            else
                root.themeJsonPresent = true;
            // A hyprland config reading either colours file must find it
            // whether or not a wallpaper was ever set, so the static
            // palette renders the same variables matugen would.
            root._publishHyprColors(palette, function () {
                root._reloadHyprland();
                root._finish();
            });
        });
    }

    function _start() {
        root._syncSystemScheme();
        if (Core.State.wallpaper === "") {
            root._publishStatic(Palette.fallback(Core.State.mode));
            return;
        }
        readConfigsProc._sawExit = false;
        readConfigsProc.command = ["sh", "-c",
            'cat "$1" 2>/dev/null; echo "$3"; for f in "$2"/*.toml; do [ -f "$f" ] && cat "$f" && echo; done',
            "sh", root._userConfigPath, root._dropInDir, root._dropInBoundary];
        readConfigsProc.running = true;
    }

    Process {
        id: readConfigsProc
        property bool _sawExit: false

        onRunningChanged: {
            if (readConfigsProc.running || readConfigsProc._sawExit)
                return;
            root._pipelineFailedToStart("sh");
        }

        stdout: StdioCollector {
            onStreamFinished: {
                readConfigsProc._sawExit = true;
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
                root._pinnedRun = Palette.pinsFlexoki(Core.State.wallpaper);
                if (root._pinnedRun) {
                    root._rewriteTemplates(cfg);
                    return;
                }
                root._publishConfig(cfg);
            }
        }
    }

    // Reads every template the merged config points at, rewrites each one's
    // colour expressions to Flexoki tones, and stages the copies for matugen
    // to render. post_hook strings are rendered by matugen's own engine too,
    // so the config text goes through the same rewrite. A config declaring no
    // template at all (nothing to rewrite) goes straight on.
    function _rewriteTemplates(cfg) {
        var rewritten = Matugen.substituteFlexoki(cfg, Core.State.mode);
        root._pinnedConfig = rewritten.text;
        root._pinnedSkipped = rewritten.skipped;
        root._pinnedInputs = Matugen.templateInputs(root._pinnedConfig).map(function (path) {
            return Matugen.expandHome(path, root._homeDir);
        });
        if (root._pinnedInputs.length === 0) {
            root._publishConfig(root._pinnedConfig);
            return;
        }
        // $0 is the boundary, $@ the paths: one Process for the whole set,
        // since Quickshell.Io reads a file at a time and a config with a
        // dozen templates would otherwise be a dozen round trips. A path that
        // cannot be read comes back as an empty section and keeps its
        // original input_path, so matugen fails on it exactly as it would
        // have without the pin.
        readTemplatesProc._sawExit = false;
        readTemplatesProc.command = ["sh", "-c",
            "for f in \"$@\"; do printf '%s\\n' \"$0\"; cat \"$f\" 2>/dev/null; done",
            root._templateBoundary].concat(root._pinnedInputs);
        readTemplatesProc.running = true;
    }

    function _writeTemplateCopies(pairs, onDone) {
        var proc = writeFileProcComponent.createObject(root, {
            _onDone: onDone
        });
        proc.command = ["sh", "-c",
            'mkdir -p "$1" || exit 1; rm -f "$1"/*.tmpl; shift; while [ "$#" -ge 2 ]; do printf \'%s\' "$2" > "$1" || exit 1; shift 2; done',
            "sh", root._flexokiDir].concat(pairs);
        proc.running = true;
    }

    // The tail both paths share: the merged config is written once, already
    // repointed at the staged copies on a pinned run, and the run that reads
    // it starts. A pinned run needs no source probe, its source is known.
    function _publishConfig(cfg) {
        root._writeFile(root._mergedConfigPath, cfg, exitCode => {
            if (exitCode !== 0) {
                console.warn("ThemeEngine: failed to write matugen-merged.toml, code", exitCode);
                root._finish();
                return;
            }
            if (root._pinnedRun) {
                matugenProc._sawExit = false;
                matugenProc.command = ["matugen", "color", "hex", Palette.FLEXOKI_SOURCE,
                    "-m", Core.State.mode, "-c", root._mergedConfigPath];
                matugenProc.running = true;
                return;
            }
            // Extraction only: --dry-run writes no template and runs
            // no command, and -d is what prints the ranking. -q would
            // silence that ranking, so it is deliberately absent.
            sourceProbeProc._sawExit = false;
            sourceProbeProc.command = ["matugen", "-d", "image", Core.State.wallpaper, "--dry-run",
                "--prefer", "saturation"];
            sourceProbeProc.running = true;
        });
    }

    Process {
        id: readTemplatesProc
        property bool _sawExit: false

        onRunningChanged: {
            if (readTemplatesProc.running || readTemplatesProc._sawExit)
                return;
            root._pipelineFailedToStart("sh");
        }

        stdout: StdioCollector {
            onStreamFinished: {
                readTemplatesProc._sawExit = true;
                var sections = text.split(root._templateBoundary + "\n");
                var staged = ({});
                var pairs = [];
                var skipped = root._pinnedSkipped.slice();
                for (var i = 0; i < root._pinnedInputs.length; i++) {
                    // sections[0] is the run-in before the first boundary.
                    var body = sections[i + 1];
                    if (!body)
                        continue;
                    var out = Matugen.substituteFlexoki(body, Core.State.mode);
                    out.skipped.forEach(function (expr) {
                        if (skipped.indexOf(expr) === -1)
                            skipped.push(expr);
                    });
                    staged[i] = root._flexokiDir + "/" + i + ".tmpl";
                    pairs.push(staged[i], out.text);
                }
                if (skipped.length > 0)
                    console.warn("ThemeEngine: Flexoki pin left", skipped.length,
                        "expression(s) on matugen's own scheme:", skipped.join(", "));
                var cfg = Matugen.rewriteTemplateInputs(root._pinnedConfig, function (path, index) {
                    return staged[index] !== undefined ? staged[index] : null;
                });
                if (pairs.length === 0) {
                    root._publishConfig(cfg);
                    return;
                }
                root._writeTemplateCopies(pairs, function (exitCode) {
                    if (exitCode !== 0) {
                        console.warn("ThemeEngine: failed to stage rewritten Flexoki templates, code", exitCode);
                        root._finish();
                        return;
                    }
                    root._publishConfig(cfg);
                });
            }
        }
    }

    Process {
        id: sourceProbeProc
        property bool _sawExit: false

        stderr: StdioCollector {
            id: sourceProbeErr
        }

        onRunningChanged: {
            if (sourceProbeProc.running || sourceProbeProc._sawExit)
                return;
            root._pipelineFailedToStart("matugen");
        }

        onExited: exitCode => {
            sourceProbeProc._sawExit = true;
            var source = exitCode === 0 ? Matugen.rankedSourceColor(sourceProbeErr.text) : null;
            if (!source)
                console.warn("ThemeEngine: no source-color ranking from matugen (code", exitCode + "), falling back to --prefer saturation");
            var pick = source
                ? ["--prefer", "closest-to-fallback", "--fallback-color", source]
                : ["--prefer", "saturation"];
            matugenProc._sawExit = false;
            matugenProc.command = ["matugen", "image", Core.State.wallpaper, "-m", Core.State.mode,
                "-c", root._mergedConfigPath].concat(pick);
            matugenProc.running = true;
        }
    }

    Process {
        id: matugenProc
        property bool _sawExit: false

        onRunningChanged: {
            if (matugenProc.running || matugenProc._sawExit)
                return;
            root._pipelineFailedToStart("matugen");
        }

        onExited: exitCode => {
            matugenProc._sawExit = true;
            if (exitCode !== 0) {
                console.warn("ThemeEngine: matugen exited with code", exitCode);
                root._finish();
                return;
            }
            if (root._pinnedRun) {
                // The rewritten templates rendered these three in Flexoki
                // too, but theme.json and both Hyprland palettes stay the
                // static write's: palette.flexoki() is the shell's own
                // authority for them (the greeter reads the same table with
                // no matugen in reach), and its chart ramp walks accents no
                // Material role carries.
                var discard = writeFileProcComponent.createObject(root, {
                    _onDone: function () {
                        root._publishStatic(Palette.flexoki(Core.State.mode));
                    }
                });
                discard.command = ["rm", "-f", root.stateDir + "/theme.json.tmp",
                    root._hyprColorsTmp, root._hyprColorsLuaTmp];
                discard.running = true;
                return;
            }
            // One mkdir covers both Hyprland paths, they share a directory.
            renameProc._sawExit = false;
            renameProc.command = ["sh", "-c",
                'mv -f "$1" "$2" && mkdir -p "$(dirname "$4")" && mv -f "$3" "$4" && mv -f "$5" "$6"',
                "sh",
                root.stateDir + "/theme.json.tmp", root._themeJsonPath,
                root._hyprColorsTmp, root._hyprColorsPath,
                root._hyprColorsLuaTmp, root._hyprColorsLuaPath];
            renameProc.running = true;
        }
    }

    Process {
        id: renameProc
        property bool _sawExit: false

        onRunningChanged: {
            if (renameProc.running || renameProc._sawExit)
                return;
            root._pipelineFailedToStart("sh");
        }

        onExited: exitCode => {
            renameProc._sawExit = true;
            if (exitCode !== 0) {
                console.warn("ThemeEngine: failed to publish theme.json/formalshell-colors.{conf,lua}, code", exitCode);
                root._finish();
                return;
            }
            root.themeJsonPresent = true;
            root._reloadHyprland();
            root._finish();
        }
    }

    // Startup probe only, reads theme.json once to detect a first run and
    // seed themeJsonPresent's initial value; writes never go through here
    // (see the FileView.setText() hazard above). Every later transition of
    // themeJsonPresent is set directly by the write sites above, not by
    // watching this file.
    FileView {
        id: themeProbe
        path: root._themeJsonPath

        onLoaded: {
            root.themeJsonPresent = true;
            root._publishHyprChrome(function () {
                root._reloadHyprland();
            });
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.themeJsonPresent = false;
                root.retheme();
            }
            root._publishHyprChrome(function () {
                root._reloadHyprland();
            });
        }
    }

    Connections {
        target: Core.State
        function onWallpaperChanged() { root.retheme(); }
        function onModeChanged() { root.retheme(); }
    }

    // A live settings.json edit moves these two without any wallpaper or mode
    // change behind it, so the chrome file has its own trigger rather than
    // riding the retheme one. Held disabled until Config.loaded (IdleService.
    // qml's own gate pattern, ~:66): Theme.radius/blurBehind read straight off
    // Config.get(), so the jump from their pre-load defaults to the real
    // settings.json values would otherwise fire this the moment Config.loaded
    // flips, right on top of themeProbe's own startup publish above.
    // _armChromeConnections() below still publishes once at arm time, since
    // themeProbe may itself have already run against the pre-load defaults
    // (its own timing is independent of Config's) -- the byte-compare in
    // _publishHyprChrome makes that catch-up call a no-op whenever nothing
    // was actually missed.
    Connections {
        id: chromeChangeConnections
        target: Core.Theme
        enabled: false
        function onRadiusChanged() {
            root._publishHyprChrome(function () {
                root._reloadHyprland();
            });
        }
        function onBlurBehindChanged() {
            root._publishHyprChrome(function () {
                root._reloadHyprland();
            });
        }
    }

    function _armChromeConnections() {
        chromeChangeConnections.enabled = true;
        root._publishHyprChrome(function () {
            root._reloadHyprland();
        });
    }

    Connections {
        target: Core.Config
        function onLoadedChanged() {
            if (Core.Config.loaded)
                root._armChromeConnections();
        }
    }

    Component.onCompleted: {
        if (Core.Config.loaded)
            root._armChromeConnections();
    }
}

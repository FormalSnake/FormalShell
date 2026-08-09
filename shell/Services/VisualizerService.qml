pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Services
import "../Visualizer/model.js" as Model

// Shared cava backend for the bar's ASCII visualizer widget (owner ask:
// "next to the now playing it would be nice to have an ASCII style audio
// visualizer"). One process for the whole shell regardless of how many
// outputs/bars exist (shell.qml's Variants instantiates one Bar per
// screen) — each bar's own Visualizer.qml cell registers its on-screen
// state here via setBarVisible() rather than owning its own process,
// since running one cava per monitor against the same system audio would
// just be duplicated work.
//
// Hard gate (DESIGN.md §4, CLAUDE.md's M16 hidden-work rule): the process
// runs ONLY while a track is actually playing AND at least one bar
// window showing the widget is on screen AND motion is enabled — paused
// music is a dead process, zero CPU, the same discipline the now-playing
// marquee's own windowVisible gate already follows. This singleton isn't
// even constructed unless "visualizer" is opted into some bar's
// bar.layout (Visualizer.qml is the only thing that references it, and it
// only loads when named — layout.js's BUILTIN_WIDGETS/DEFAULT_LAYOUT
// split), so an unconfigured shell touches none of this.
//
// cava's own raw output format (verified against its 0.10.7 example
// config, not memory): [output] method=raw writes bar heights to
// raw_target either as binary or as ascii text, one frame (line) of
// `;`-delimited 0..ascii_max_range values per line, `\n`-terminated.
// ascii, not binary, is what SplitParser can parse robustly here — a
// binary stream can contain the newline byte value inside a bar's own
// value, which would corrupt a line-based split; ascii text has no such
// collision. raw_target is pointed at /dev/stdout so this Process's own
// stdout is the data stream, with no fifo file to create or clean up.
Singleton {
    id: root

    readonly property string _runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/formalshell"
    readonly property string _configPath: root._runtimeDir + "/cava.conf"

    // "unknown" until the one-shot PATH probe below answers, mirroring
    // GithubWidget/UsageWidget's own pre-first-answer hidden state — never
    // guessed. "available" or "missing" after.
    property string state: "unknown"

    // Ref-counted by Visualizer.qml instances (one per bar that opts the
    // widget in) via setBarVisible(). Symmetric add/remove calls only —
    // each caller tracks its own last-reported bool and only calls on a
    // real transition, so this can never drift from the true count.
    property int _visibleBars: 0

    function setBarVisible(wasVisible, isVisible) {
        if (wasVisible === isVisible)
            return;
        root._visibleBars += isVisible ? 1 : -1;
    }

    readonly property bool _shouldRun: root.state === "available" && MediaService.isPlaying && root._visibleBars > 0 && Theme.motionEnabled

    // Rendered levels for the current frame — one 0..1 fill fraction per
    // bar, reset to the all-zero baseline array the instant the process
    // isn't running, so a paused/hidden widget never shows a frozen "still
    // playing" frame.
    property var levels: Model.baselineLevels()

    // Every key below is in cava 0.10.7's own example config (checked there,
    // not from memory), and every one that departs from cava's default does
    // so for a stated reason. The tuning is DMS's (`Services/CavaService.qml`)
    // — the owner's reference for how this should feel — reworked onto this
    // shell's own 0..MAX_LEVEL output range and without DMS's three
    // deprecated smoothing keys.
    //
    //   autosens = 0 + sensitivity     autosens continuously renormalizes so
    //     a quiet passage gets boosted to the same full-scale row as a loud
    //     one, which is exactly the "always maxed, never responds" feel.
    //     Fixed gain instead, so loudness reads as height again. 800% is
    //     measured, not inherited: pink noise through this exact config lands
    //     at ▄▅▅▆▇█ for a loud passage (amplitude 0.8) and ▃▃▄▄▄▅ for a quiet
    //     one (0.3), which spends the glyph range without pegging. DMS's own
    //     number works out to ~300% here (its 30% reads against a 0..1000
    //     range it then clamps at 100 in QML), and 300% measures out at
    //     ▃▃▃▄▄▅ / ▂▂▃▃▃▃ — fine for DMS's continuous shader bars, but this
    //     row only has eight discrete steps and the bottom three are all
    //     near-flat strokes, so it needs more of the range to read at all.
    //   higher_cutoff_freq             12kHz over cava's 10kHz default: pulls
    //     hi-hats and cymbals into the top bar instead of leaving it dead on
    //     most tracks.
    //   noise_reduction = 35           cava's 77 default is heavily smoothed
    //     and reads laggy at 6 bars; 35 tracks transients.
    //   monstercat = 1.5               bleeds each bar's energy into its
    //     neighbours, so six bars read as one connected spectrum rather than
    //     six independent meters. This is the single most visible difference
    //     from an untuned cava.
    //   sleep_timer = 3                cava idles itself after 3s of silence.
    //     The _shouldRun gate already kills the process on pause; this covers
    //     silence *inside* a playing track.
    //
    // DMS's `integral`/`gravity`/`ignore` are deliberately not carried over:
    // all three have been deprecated in favour of noise_reduction since cava
    // 0.8.0. The `ignore` behaviour lives in model.js's NOISE_FLOOR instead.
    function _configText() {
        return "[general]\n" +
            "framerate = 25\n" +
            "autosens = 0\n" +
            "sensitivity = 800\n" +
            "bars = " + Model.BAR_COUNT + "\n" +
            "lower_cutoff_freq = 50\n" +
            "higher_cutoff_freq = 12000\n" +
            "sleep_timer = 3\n" +
            "\n" +
            "[input]\n" +
            "method = pipewire\n" +
            "source = auto\n" +
            "\n" +
            "[output]\n" +
            "method = raw\n" +
            "channels = mono\n" +
            "mono_option = average\n" +
            "raw_target = /dev/stdout\n" +
            "data_format = ascii\n" +
            "ascii_max_range = " + Model.MAX_LEVEL + "\n" +
            "\n" +
            "[smoothing]\n" +
            "noise_reduction = 35\n" +
            "monstercat = 1.5\n";
    }

    Component.onCompleted: mkdirProc.running = true

    // mkdir -> write cava.conf -> probe `cava` on PATH, strictly ordered
    // (InstanceLock.qml's own runtime-dir bootstrap idiom) since the probe
    // and the real process below both need the config file to already
    // exist.
    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root._runtimeDir]
        onExited: writeConfigProc.running = true
    }

    // printf-to-file, never FileView.setText() (ThemeEngine.qml's own
    // documented hazard: FileView silently skips both the write and its
    // saved() signal when the new text is byte-identical to what's
    // already on disk, which this config always is after the first run).
    Process {
        id: writeConfigProc
        command: ["sh", "-c", 'printf \'%s\' "$2" > "$1"', "sh", root._configPath, root._configText()]
        onExited: probeProc.running = true
    }

    Process {
        id: probeProc
        command: ["sh", "-c", "command -v cava >/dev/null 2>&1"]
        onExited: exitCode => root.state = exitCode === 0 ? "available" : "missing"
    }

    // Declaratively bound to the hard gate above — Process.running's own
    // documented behavior (CommandModule.qml/NetworkPanel.qml) sends
    // SIGTERM the instant _shouldRun drops, no manual stop() needed. The
    // `command -v` guard is defense in depth against cava vanishing from
    // PATH between the probe above and a later run, not the primary
    // availability check.
    Process {
        id: cavaProc
        running: root._shouldRun
        command: ["sh", "-c", 'command -v cava >/dev/null 2>&1 || exit 127; exec cava -p "$1"', "sh", root._configPath]
        stdout: SplitParser {
            onRead: line => root.levels = Model.frameToLevels(line, Model.BAR_COUNT, Model.MAX_LEVEL)
        }
        onRunningChanged: {
            if (!cavaProc.running)
                root.levels = Model.baselineLevels();
        }
    }
}

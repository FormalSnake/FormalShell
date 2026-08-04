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

    // Rendered text for the current frame — reset to the all-baseline
    // glyph row the instant the process isn't running, so a paused/hidden
    // widget never shows a frozen "still playing" frame.
    property string frameText: Model.baselineText()

    function _configText() {
        return "[general]\n" +
            "framerate = 20\n" +
            "autosens = 1\n" +
            "bars = " + Model.BAR_COUNT + "\n" +
            "\n" +
            "[input]\n" +
            "method = pipewire\n" +
            "source = auto\n" +
            "\n" +
            "[output]\n" +
            "method = raw\n" +
            "channels = mono\n" +
            "raw_target = /dev/stdout\n" +
            "data_format = ascii\n" +
            "ascii_max_range = " + Model.MAX_LEVEL + "\n";
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
            onRead: line => root.frameText = Model.frameToText(line, Model.BAR_COUNT, Model.MAX_LEVEL)
        }
        onRunningChanged: {
            if (!cavaProc.running)
                root.frameText = Model.baselineText();
        }
    }
}

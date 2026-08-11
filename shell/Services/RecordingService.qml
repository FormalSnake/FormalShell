pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core
import qs.Compositor
import qs.Notifications
import "../Capture/model.js" as Capture

// Screen recording (M22): one wf-recorder child, the transient
// PipeWire/Pulse mix modules the desktop+mic mode needs, and the two-pass
// ffmpeg GIF transcode. Driven over the `record` IPC target (RecordIpc.qml)
// and read by the bar's recording indicator; the service/IPC split mirrors
// NightLightService.qml exactly.
//
// `active` is `recProc.running` and nothing else. It is never persisted to
// state.json (a crashed shell would leave a stale `true` behind) and never
// derived from `pgrep` (omarchy polls for its own recorder that way; a live
// QML binding on the child this shell owns is both cheaper and correct).
//
// wf-recorder rather than gpu-screen-recorder: gpu-screen-recorder captures
// through the KMS backend, which has no meaning inside a nested compositor
// or on llvmpipe, so it could never be verified in the smoke rig.
// wf-recorder speaks wlr-screencopy-unstable-v1, which niri implements
// under its nested winit backend, so the same code path the owner runs is
// the one the rig exercises.
//
// Audio, honestly scoped:
//   none        no audio flag at all.
//   desktop     the default sink's own monitor.
//   desktopmic  wf-recorder stores exactly ONE audio source (src/main.cpp),
//               so there is no multi-device form. A transient null sink
//               plus two loopbacks mix the sink monitor and the microphone
//               into one device, and the module ids are unloaded on stop.
//               A rig with a synthetic source proves the combine round trip
//               and the two-source mux; a real microphone stays host-trial.
// Requesting desktopmic where the default source is itself a monitor fails
// loudly instead of quietly recording desktop audio twice.
//
// No webcam overlay. Compositing a camera into the frame needs the camera
// window to float at a fixed corner, which is a compositor window rule this
// shell does not install and cannot install portably (niri window-rule vs
// Hyprland windowrulev2). Half of it (spawning an mpv window that then
// tiles across the recording) would be worse than not having it.
Singleton {
    id: root

    readonly property bool active: recProc.running
    readonly property bool transcoding: paletteProc.running || gifProc.running

    // "screen" | "region", and "none" | "desktop" | "desktopmic": what the
    // current (or most recent) run was asked for.
    property string scope: "screen"
    property string audioMode: "none"

    property string lastPath: ""
    // What a caller should look at right now: the destination a live run is
    // writing toward, or the last finished file once it isn't.
    readonly property string path: root.active ? root._pendingPath : root.lastPath
    property string lastGifPath: ""
    property string lastError: ""
    property real startedMs: 0

    property real _nowMs: 0
    readonly property int elapsedMs: root.active && root.startedMs > 0
        ? Math.max(0, root._nowMs - root.startedMs)
        : 0

    readonly property string _runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/formalshell"
    // Single reused temp file on the runtime tmpfs, overwritten by every
    // transcode and gone with the session, so there is no cleanup child.
    readonly property string _palettePath: root._runtimeDir + "/gif-palette.png"

    property string _pendingPath: ""
    property string _pendingGeometry: ""
    property string _pendingGifPath: ""
    property var _pendingGifPass2: []
    property var _audioModules: []
    property bool _stopping: false
    property bool _cancelling: false
    property bool _sawExit: false
    property bool _killed: false

    function _dir() {
        return Core.Config.get("recording.directory", "")
            || (Quickshell.env("HOME") + "/Videos");
    }

    // Returns the destination path the run is writing toward, or an
    // "error: ..." string. IpcHandler replies are synchronous, so a region
    // scope (which blocks on a human answering slurp) can only ever answer
    // with its destination, the same contract ScreenshotIpc.region() has.
    function start(scopeArg, audioArg) {
        if (recProc.running)
            return "error: already recording";
        if (slurpProc.running || mkdirProc.running || audioProc.running)
            return "error: a recording start is already in flight";

        const wantScope = scopeArg || "screen";
        if (wantScope !== "screen" && wantScope !== "region")
            return "error: unknown scope \"" + wantScope + "\" (screen|region)";
        const wantAudio = audioArg || "none";
        if (["none", "desktop", "desktopmic"].indexOf(wantAudio) < 0)
            return "error: unknown audio mode \"" + wantAudio + "\" (none|desktop|desktopmic)";

        root.scope = wantScope;
        root.audioMode = wantAudio;
        root.lastError = "";
        root._pendingGeometry = "";
        root._pendingPath = Capture.outputPath(root._dir(), "screenrecording", "mp4", new Date());

        if (wantScope === "region") {
            // Same slurp chrome and the same stdin trap as ScreenshotIpc's
            // region path: slurp reads stdin to EOF before touching wayland
            // whenever stdin is not a tty, and quickshell's pipe never
            // closes, so 0</dev/null is what keeps the overlay from never
            // appearing at all.
            slurpProc.environment = ({
                FS_SLURP_BG: Core.Theme.color.background + "99",
                FS_SLURP_BORDER: Core.Theme.color.urgent + "FF",
                FS_SLURP_SEL: "#00000000",
                FS_SLURP_WEIGHT: "" + Core.Theme.borderWidth
            });
            slurpProc.command = ["sh", "-c",
                'exec slurp -d -w "$FS_SLURP_WEIGHT" -b "$FS_SLURP_BG" -c "$FS_SLURP_BORDER" -s "$FS_SLURP_SEL" 0</dev/null'];
            slurpProc.running = true;
            regionWatchdog.interval = Core.Config.get("recording.timeoutSeconds", 90) * 1000;
            regionWatchdog.restart();
            return root._pendingPath;
        }

        root._prepareDirectory();
        return root._pendingPath;
    }

    // Cancels a pending region selection when one is up, otherwise ends the
    // recording. `running = false` is QProcess::terminate(), i.e. SIGTERM,
    // which is one of wf-recorder's own graceful-termination signals
    // (src/main.cpp GRACEFUL_TERMINATION_SIGNALS), so the container is
    // finalized rather than truncated, so no `exec`-through-sh wrapper is
    // needed and the argv stays a plain one.
    function stop() {
        if (slurpProc.running) {
            regionWatchdog.stop();
            root._cancelling = true;
            slurpProc.running = false;
            root._pendingPath = "";
            return "ok";
        }
        if (!recProc.running)
            return "error: not recording";
        root._stopping = true;
        recProc.running = false;
        killTimer.restart();
        return "ok";
    }

    function toggle(scopeArg, audioArg) {
        if (recProc.running || slurpProc.running)
            return root.stop();
        return root.start(scopeArg, audioArg);
    }

    // `path` defaults to the last recording, so a keybind straight after a
    // stop needs no argument.
    function gif(path) {
        if (root.transcoding)
            return "error: a transcode is already running";
        const source = path || root.lastPath;
        if (!source)
            return "error: no recording to convert";
        const out = Capture.gifOutputPath(source);
        const argv = Capture.gifArgv(source, root._palettePath, out, {
            fps: Core.Config.get("recording.gifFps", 12),
            width: Core.Config.get("recording.gifWidth", 640)
        });
        root.lastError = "";
        root._pendingGifPath = out;
        root._pendingGifPass2 = argv.pass2;
        paletteProc.command = argv.pass1;
        paletteProc.running = true;
        return out;
    }

    function _prepareDirectory() {
        mkdirProc.command = ["mkdir", "-p", root._dir()];
        mkdirProc.running = true;
    }

    // pactl is a one-shot client, so the whole audio setup is one script
    // rather than a chain of children. Nothing user-controlled reaches the
    // script text: the one value it needs is the fixed mix-sink name, and
    // that rides the environment. It answers on two lines, the pactl module
    // ids it loaded then the device wf-recorder should record, and it
    // unloads whatever it already loaded when a later step fails, so a
    // half-built mix never leaks. Exit 5 is the distinct "there is no real
    // microphone on this machine" answer.
    function _setupAudio() {
        if (root.audioMode === "none") {
            root._launch("");
            return;
        }
        const desktop =
            'sink=$(pactl get-default-sink) || exit 4\n' +
            '[ -n "$sink" ] || exit 4\n' +
            'printf \'\\n%s.monitor\\n\' "$sink"\n';
        const desktopMic =
            'sink=$(pactl get-default-sink) || exit 4\n' +
            'src=$(pactl get-default-source) || exit 4\n' +
            '[ -n "$sink" ] && [ -n "$src" ] || exit 4\n' +
            'case "$src" in *.monitor) exit 5 ;; esac\n' +
            'm1=$(pactl load-module module-null-sink sink_name="$FS_MIX" sink_properties=device.description="$FS_MIX") || exit 4\n' +
            'm2=$(pactl load-module module-loopback source="$sink".monitor sink="$FS_MIX" latency_msec=50) || { pactl unload-module "$m1"; exit 4; }\n' +
            'm3=$(pactl load-module module-loopback source="$src" sink="$FS_MIX" latency_msec=50) || { pactl unload-module "$m2"; pactl unload-module "$m1"; exit 4; }\n' +
            'printf \'%s %s %s\\n%s.monitor\\n\' "$m1" "$m2" "$m3" "$FS_MIX"\n';
        audioProc.environment = ({ FS_MIX: Capture.MIX_SINK });
        audioProc.command = ["sh", "-c", root.audioMode === "desktopmic" ? desktopMic : desktop];
        audioProc.running = true;
    }

    function _launch(device) {
        // Never omit -o: on a multi-output host wf-recorder would pick one
        // itself, and inside a nested session the nested output is the only
        // correct answer. Taken at call time, never cached.
        recProc.command = Capture.recorderArgv({
            path: root._pendingPath,
            framerate: Core.Config.get("recording.framerate", 30),
            output: CompositorService.focusedOutputName,
            geometry: root._pendingGeometry,
            codec: Core.Config.get("recording.codec", ""),
            noDmabuf: Core.Config.get("recording.noDmabuf", false) === true,
            audioDevice: device,
            audioBackend: Core.Config.get("recording.audioBackend", "")
        });
        root.startedMs = Date.now();
        root._nowMs = root.startedMs;
        root._stopping = false;
        root._sawExit = false;
        recProc.running = true;
    }

    function _releaseAudio() {
        if (root._audioModules.length === 0)
            return;
        // Reverse order: the loopbacks come out before the sink they feed.
        // $FS_MODULES is deliberately unquoted so the shell splits it: the
        // values are integers parseAudioSetup() already validated.
        unloadProc.environment = ({ FS_MODULES: root._audioModules.slice().reverse().join(" ") });
        root._audioModules = [];
        unloadProc.command = ["sh", "-c", 'for m in $FS_MODULES; do pactl unload-module "$m"; done'];
        unloadProc.running = true;
    }

    function _fail(why) {
        regionWatchdog.stop();
        root._pendingPath = "";
        root._pendingGeometry = "";
        root.lastError = why;
        root._releaseAudio();
        console.warn("RecordingService:", why);
        NotificationService.notify("RECORDING FAILED", why);
    }

    Component.onCompleted: runtimeDirProc.running = true

    Process {
        id: runtimeDirProc
        command: ["mkdir", "-p", root._runtimeDir]
    }

    Timer {
        running: root.active
        interval: 1000
        repeat: true
        onTriggered: root._nowMs = Date.now()
    }

    // SIGTERM asks wf-recorder to finalize the container; this is the
    // escalation if it never does, so a wedged encoder can't leave `active`
    // stuck on forever.
    Timer {
        id: killTimer
        interval: 5000
        onTriggered: {
            if (!recProc.running)
                return;
            root._killed = true;
            recProc.signal(9);
        }
    }

    Timer {
        id: regionWatchdog
        onTriggered: {
            root._cancelling = true;
            slurpProc.running = false;
            root._pendingPath = "";
            NotificationService.notify("RECORDING CANCELLED",
                "no region after " + Math.round(regionWatchdog.interval / 1000) + "s");
        }
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
            regionWatchdog.stop();
            const geometry = Capture.parseGeometry(slurpOut.text);
            if (exitCode === 0 && geometry !== "") {
                root._pendingGeometry = geometry;
                root._prepareDirectory();
                return;
            }
            root._pendingPath = "";
            if (exitCode === 1)
                return; // slurp's own Escape/right-click exit: a decline, not a failure
            root._fail(slurpErr.text.trim()
                || (exitCode === 0 ? "slurp reported no geometry" : "slurp exited " + exitCode));
        }
    }

    Process {
        id: mkdirProc

        stderr: StdioCollector {
            id: mkdirErr
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                root._setupAudio();
                return;
            }
            root._fail(mkdirErr.text.trim() || ("could not create " + root._dir()));
        }
    }

    Process {
        id: audioProc

        stdout: StdioCollector {
            id: audioOut
        }
        stderr: StdioCollector {
            id: audioErr
        }
        onExited: exitCode => {
            if (exitCode === 5) {
                root._fail("no microphone: the default source is a monitor");
                return;
            }
            const setup = Capture.parseAudioSetup(audioOut.text);
            if (exitCode !== 0 || setup.device === "") {
                root._fail(audioErr.text.trim() || ("audio setup exited " + exitCode));
                return;
            }
            root._audioModules = setup.modules;
            root._launch(setup.device);
        }
    }

    Process {
        id: unloadProc
    }

    Process {
        id: recProc

        stderr: StdioCollector {
            id: recErr
        }

        onRunningChanged: {
            if (recProc.running)
                return;
            // quickshell's Process emits no `exited` when the command never
            // starts (NightLightService.qml's own learned idiom:
            // onErrorOccurred only emits runningChanged for FailedToStart),
            // so a missing wf-recorder lands here rather than below.
            if (!root._sawExit && !root._stopping)
                root._fail("wf-recorder not found (failed to start)");
        }

        onExited: exitCode => {
            root._sawExit = true;
            killTimer.stop();
            root._releaseAudio();
            const saved = root._pendingPath;
            root._pendingPath = "";
            root._pendingGeometry = "";
            const wasStopping = root._stopping;
            root._stopping = false;
            if (root._killed) {
                // SIGKILL cut the muxer off mid-container, so the file on
                // disk is whatever wf-recorder had already flushed. Say
                // that rather than reporting a save.
                root._killed = false;
                root.lastPath = saved;
                root.lastError = "wf-recorder ignored SIGTERM and was killed; " + saved + " may be truncated";
                console.warn("RecordingService:", root.lastError);
                NotificationService.notify("RECORDING TRUNCATED", root.lastError);
                return;
            }
            if (exitCode !== 0 && !wasStopping) {
                root.lastError = recErr.text.trim() || ("wf-recorder exited " + exitCode);
                console.warn("RecordingService:", root.lastError);
                NotificationService.notify("RECORDING FAILED", root.lastError);
                return;
            }
            root.lastPath = saved;
            root.lastError = "";
            NotificationService.notify("RECORDING SAVED", saved, 1, [{
                key: "default",
                label: "GIF",
                invoke: () => root.gif(saved)
            }]);
        }
    }

    Process {
        id: paletteProc

        stderr: StdioCollector {
            id: paletteErr
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                gifProc.command = root._pendingGifPass2;
                gifProc.running = true;
                return;
            }
            root.lastError = paletteErr.text.trim() || ("palettegen exited " + exitCode);
            console.warn("RecordingService:", root.lastError);
            NotificationService.notify("GIF FAILED", root.lastError);
        }
    }

    Process {
        id: gifProc

        stderr: StdioCollector {
            id: gifErr
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.lastGifPath = root._pendingGifPath;
                root.lastError = "";
                NotificationService.notify("GIF SAVED", root.lastGifPath, 1, [], root.lastGifPath);
                return;
            }
            root.lastError = gifErr.text.trim() || ("paletteuse exited " + exitCode);
            console.warn("RecordingService:", root.lastError);
            NotificationService.notify("GIF FAILED", root.lastError);
        }
    }
}

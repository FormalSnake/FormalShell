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
// Finalize, after wf-recorder exits and before the SAVED notification:
// upstream's own PipeWire-click fix (bin/omarchy-capture-screenrecording's
// finalize_recording, MIT), ported because it is pure ffmpeg and
// compositor-neutral. Trims the first 0.1s, re-encoding only when the first
// GOP holds discardable warmup packets a stream copy can't cut, and
// hard-mutes/fades/loudnorms the audio track when there is one. Never
// fatal: a probe or ffmpeg failure keeps the raw file wf-recorder already
// wrote. recording.finalize (default true) turns the whole pass off.
//
// SAVED toast: a one-frame ffmpeg thumbnail attached as the notification's
// image (upstream's own omarchy-capture-screenrecording:224-239, MIT),
// deleted 2s later since Toasts.qml loads it into memory once and never
// re-reads the path. A PLAY action opens the file with recording.player
// (default xdg-open), the same env+sh handoff screenshot.editor already
// establishes; GIF stays alongside it as a second action, M27 Task 3.
//
// recording.maxHeight (default 0, no cap) downscales via wf-recorder's own
// -F filter (model.js's scaleCapFilter) when the captured source is taller
// than it, preserving aspect ratio. `record startCapped` overrides it for
// one run without editing config; every other entry point (start, startAt,
// the picker's own REC tools) still resolves the config default. M27 Task 4.
//
// Webcam overlay (recording.webcam, default off): spawned right before
// _launch, not alongside it, since the recording must not start until the
// camera has actually mapped and settled into its corner -- filming it
// slide into place is worse than a beat of extra wait. Placement goes
// through CompositorService.floatWindow/placeFloatingWindow
// (CompositorService.qml, backends in shell/Compositor/{niri,hyprland}),
// each backend's own primitive for "float this window, then resize and move
// it to an absolute pixel rect". A backend with no such primitive
// (floatingPlacementAvailable false -- the null backend's answer whenever no
// compositor was detected at all) never sees mpv spawned in the first
// place: half a webcam overlay, a camera window that tiles across the
// recording, is worse than none. Two bounded polls stand in for upstream's
// blind "wait for the client, then sleep 600ms" (bin/omarchy-capture-
// screenrecording:96-104, MIT) -- one for the window to map (matched by its
// own app id, since spawning gives no window id up front), one for its rect
// to actually reach the requested size after placement -- each reporting an
// honest WEBCAM UNAVAILABLE/WEBCAM UNPLACED notification and recording
// anyway on expiry, never blocking the primary capture on a camera that
// never showed up. The map poll itself is two-phase (Capture.
// webcamMapPollAction): mpv is already spawned by the time it gives up, so
// after the honest notification it keeps watching a while longer purely to
// close a straggler window that maps late instead of leaking it into the
// recording untracked.
Singleton {
    id: root

    readonly property bool active: recProc.running
    readonly property bool transcoding: paletteProc.running || gifProc.running
    // True from the moment a finished recording starts through finalize
    // until the SAVED notification fires. `record status` exposes this so a
    // caller can wait for the rewrite to settle instead of guessing a delay
    // (the same poll-don't-sleep contract `active` already holds).
    property bool finalizing: false

    // "screen" | "region" | "window", and "none" | "desktop" | "desktopmic":
    // what the current (or most recent) run was asked for. "window" only ever
    // arrives through startAt() — a window is a rectangle to wf-recorder, so
    // it is a scope label for `record status`, never a different pipeline.
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
    // The output a caller-supplied geometry sits on. Empty means "the focused
    // one", which is every path that resolves its own rectangle.
    property string _pendingOutput: ""
    property string _pendingGifPath: ""
    property var _pendingGifPass2: []
    // Resolved once per start/startAt call and read at launch time, so a
    // config change mid-recording can't retroactively change what
    // `_launch` builds -F around.
    property real _pendingMaxHeight: 0
    property string _finalizeSource: ""
    property string _finalizeProcessed: ""
    property bool _finalizeReencode: false
    property string _previewSource: ""
    property string _previewCleanupPath: ""
    // Webcam overlay state (M27 Task 5). _webcamTarget/_webcamAudioDevice are
    // resolved once per start and read back by the two poll timers below;
    // _webcamWindowId is "" whenever no overlay is live, the flag
    // recProc.onExited/onRunningChanged read to know whether there is
    // anything left to close.
    readonly property string _webcamAppId: "formalshell-webcam"
    property string _webcamWindowId: ""
    property var _webcamTarget: null
    property string _webcamAudioDevice: ""
    property bool _webcamPlaced: false
    property int _webcamAttempts: 0
    // True once webcamMapTimer has given up waiting and launched the
    // recording without the camera. The timer keeps running past that point
    // in reap mode: a window that maps late is closed on sight rather than
    // left untracked over the recording.
    property bool _webcamGaveUp: false
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
    //
    // maxHeightArg is undefined from the plain 2-arg `record start`/`toggle`
    // callers (defers to recording.maxHeight) and a string from
    // RecordIpc.startCapped, which overrides it for this one run without
    // touching config -- its own verb rather than a third argument on
    // `start` itself, since IpcHandler dispatches on exact arity and a
    // defaulted parameter would break the bare `record start` a keybind
    // already calls (M27 Task 4).
    function start(scopeArg, audioArg, maxHeightArg) {
        if (recProc.running)
            return "error: already recording";
        if (slurpProc.running || mkdirProc.running || audioProc.running || root._webcamWindowId !== "" || webcamMapTimer.running || webcamSettleTimer.running)
            return "error: a recording start is already in flight";

        const wantScope = scopeArg || "screen";
        if (wantScope !== "screen" && wantScope !== "region")
            return "error: unknown scope \"" + wantScope + "\" (screen|region)";
        const wantAudio = audioArg || "none";
        if (["none", "desktop", "desktopmic"].indexOf(wantAudio) < 0)
            return "error: unknown audio mode \"" + wantAudio + "\" (none|desktop|desktopmic)";
        const maxHeight = Capture.resolveMaxHeight(maxHeightArg, Core.Config.get("recording.maxHeight", 0));
        if (isNaN(maxHeight))
            return "error: not a number: \"" + maxHeightArg + "\" (maxHeight)";

        root.scope = wantScope;
        root.audioMode = wantAudio;
        root._pendingMaxHeight = maxHeight;
        root.lastError = "";
        root._pendingGeometry = "";
        root._pendingOutput = "";
        root._pendingPath = Capture.outputPath(root._dir(), "screenrecording", "mp4", new Date());

        if (wantScope === "region") {
            // Same slurp chrome and the same stdin trap as ScreenshotIpc's
            // region path: slurp reads stdin to EOF before touching wayland
            // whenever stdin is not a tty, and quickshell's pipe never
            // closes, so 0</dev/null is what keeps the overlay from never
            // appearing at all.
            slurpProc.environment = ({
                FS_SLURP_BG: Core.Theme.color.background + "99",
                FS_SLURP_BORDER: Core.Theme.color.destructive + "FF",
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

    // Start against a rectangle the caller already resolved, skipping the
    // selection entirely. `opts`:
    //   geometry  "X,Y WxH" in logical compositor coordinates (required)
    //   output    the output that rectangle sits on; empty means the focused
    //             one, and wf-recorder is always pinned to exactly one
    //   scope     what `record status` reports: screen|region|window
    //   audio     none|desktop|desktopmic
    //
    // This is how the capture picker's RECORD tools start a run (its toolbar
    // has already resolved the window or display box, and slurp has no part in
    // it), and how the smoke rig drives a region recording without a pointer
    // to answer slurp with — the same split `capture textAt` and `picker
    // choose` already use. An object rather than four positional arguments
    // because only the IPC boundary needs scalars.
    function startAt(opts) {
        if (recProc.running)
            return "error: already recording";
        if (slurpProc.running || mkdirProc.running || audioProc.running || root._webcamWindowId !== "" || webcamMapTimer.running || webcamSettleTimer.running)
            return "error: a recording start is already in flight";

        const asked = (opts && opts.geometry) || "";
        const geometry = Capture.parseGeometry(asked);
        if (geometry === "")
            return "error: not a geometry: \"" + asked + "\" (expected \"X,Y WxH\")";
        const wantScope = (opts && opts.scope) || "region";
        if (["screen", "region", "window"].indexOf(wantScope) < 0)
            return "error: unknown scope \"" + wantScope + "\" (screen|region|window)";
        const wantAudio = (opts && opts.audio) || "none";
        if (["none", "desktop", "desktopmic"].indexOf(wantAudio) < 0)
            return "error: unknown audio mode \"" + wantAudio + "\" (none|desktop|desktopmic)";
        const maxHeight = Capture.resolveMaxHeight(opts && opts.maxHeight, Core.Config.get("recording.maxHeight", 0));
        if (isNaN(maxHeight))
            return "error: not a number: \"" + opts.maxHeight + "\" (maxHeight)";

        root.scope = wantScope;
        root.audioMode = wantAudio;
        root._pendingMaxHeight = maxHeight;
        root.lastError = "";
        root._pendingGeometry = geometry;
        root._pendingOutput = (opts && opts.output) || "";
        root._pendingPath = Capture.outputPath(root._dir(), "screenrecording", "mp4", new Date());
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

    // Hands the finished file to the user's configured player. Same env+sh
    // handoff ScreenshotIpc.edit() uses for screenshot.editor, so the two
    // are one idiom rather than two.
    function play(path) {
        if (!path)
            return "error: no path";
        playerProc.environment = ({
            FS_PLAYER: Core.Config.get("recording.player", "xdg-open"),
            FS_PLAY_PATH: path
        });
        playerProc.command = ["sh", "-c", 'exec "$FS_PLAYER" "$FS_PLAY_PATH"'];
        playerProc.running = true;
        return "ok";
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
            root._setupWebcam("");
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
        // correct answer. Taken at call time, never cached. A caller-supplied
        // rectangle brings its own output (startAt), since the rectangle it
        // picked need not be on the focused one.
        recProc.command = Capture.recorderArgv({
            path: root._pendingPath,
            framerate: Core.Config.get("recording.framerate", 30),
            output: root._pendingOutput || CompositorService.focusedOutputName,
            geometry: root._pendingGeometry,
            codec: Core.Config.get("recording.codec", ""),
            maxHeight: root._pendingMaxHeight,
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

    // Chained in place of a direct _launch() from both of _setupAudio's own
    // call sites, so a config change to recording.webcam takes effect on the
    // very next recording with no other call site touched.
    function _setupWebcam(device) {
        root._webcamAudioDevice = device;
        if (Core.Config.get("recording.webcam", false) !== true) {
            root._launch(device);
            return;
        }
        if (!CompositorService.floatingPlacementAvailable) {
            console.warn("RecordingService: webcam overlay unavailable: compositor cannot place a floating window");
            NotificationService.notify("WEBCAM UNAVAILABLE", "this compositor cannot place a floating window");
            root._launch(device);
            return;
        }
        const region = root._webcamRegion();
        if (!region) {
            console.warn("RecordingService: webcam overlay unavailable: could not resolve the captured region");
            NotificationService.notify("WEBCAM UNAVAILABLE", "could not resolve the captured region");
            root._launch(device);
            return;
        }
        root._webcamTarget = Capture.webcamGeometry(
            Core.Config.get("recording.webcamSize", "medium"), region, Core.Theme.space.huge);
        const configured = Core.Config.get("recording.webcamDevice", "");
        if (configured) {
            root._startWebcamOverlay(configured);
            return;
        }
        webcamListProc.command = ["sh", "-c", 'for f in /dev/video*; do [ -e "$f" ] && echo "$f"; done'];
        webcamListProc.running = true;
    }

    // The rectangle the webcam anchors against: a region/window recording's
    // own resolved geometry, or the target output's full box for scope
    // "screen" -- the same output _launch below pins wf-recorder's -o to.
    // Quickshell.screens, not CompositorService.outputs: the latter's
    // width/height are the OUTPUT MODE's physical pixels (DisplayPanel's own
    // need, outputs.js), while windows[].rect and the placement dispatchers
    // both work in logical pixels -- the exact split RegionPicker.qml's own
    // _focusedOutputRect() already resolves this same way. Quickshell.screens
    // is a QML list, not a JS array (RegionPicker's own comment), hence the
    // indexed loop rather than .find.
    function _webcamRegion() {
        if (root._pendingGeometry)
            return Capture.regionFromGeometry(root._pendingGeometry);
        const outName = root._pendingOutput || CompositorService.focusedOutputName;
        const screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === outName)
                return { x: screens[i].x, y: screens[i].y, width: screens[i].width, height: screens[i].height };
        }
        return null;
    }

    function _startWebcamOverlay(devicePath) {
        root._webcamAttempts = 0;
        root._webcamGaveUp = false;
        root._webcamPlaced = false;
        root._webcamWindowId = "";
        CompositorService.spawn(Capture.webcamArgv(devicePath, root._webcamAppId));
        webcamMapTimer.restart();
    }

    // Closes whatever overlay window is still tracked, if any. Called from
    // every recProc exit path (recording ended, was killed, or never started
    // at all) so the camera never outlives the recording it was placed for.
    function _cleanupWebcam() {
        if (root._webcamWindowId === "")
            return;
        CompositorService.closeWindow(root._webcamWindowId);
        root._webcamWindowId = "";
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
        root._pendingOutput = "";
        root.lastError = why;
        root._releaseAudio();
        console.warn("RecordingService:", why);
        NotificationService.notify("RECORDING FAILED", why);
    }

    // Entry point once wf-recorder has exited clean. recording.finalize
    // off skips straight to the notification, unchanged from before this
    // pass existed.
    function _finalize(path) {
        if (Core.Config.get("recording.finalize", true) !== true) {
            root._announceSaved(path);
            return;
        }
        root.finalizing = true;
        root._finalizeSource = path;
        finalizeProbeVideoProc.command = ["ffprobe", "-v", "error", "-select_streams", "v:0",
            "-read_intervals", "%+0.2", "-show_entries", "packet=flags", "-of", "csv=p=0", path];
        finalizeProbeVideoProc.running = true;
    }

    // The file itself is already fully settled here (finalizeCleanupProc's
    // `mv` has already exited), so the frame grab below reads the same bytes
    // the user's player will. `finalizing` drops immediately rather than
    // staying true through the grab: that flag is about the finalize
    // rewrite, and this is a read against a file nothing is rewriting.
    function _announceSaved(path) {
        root.finalizing = false;
        root._previewSource = path;
        previewProc.command = Capture.previewFrameArgv(path, Capture.previewFramePath(path));
        previewProc.running = true;
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

    // Auto-detect device listing (recording.webcamDevice empty). A separate
    // Process rather than folded into audioProc's sh script: this one only
    // runs when recording.webcam is on, so a session that never touches the
    // feature never spawns it.
    Process {
        id: webcamListProc

        stdout: StdioCollector {
            id: webcamListOut
        }
        onExited: exitCode => {
            const devices = Capture.parseWebcamDevices(webcamListOut.text);
            if (devices.length === 0) {
                console.warn("RecordingService: webcam overlay unavailable: no /dev/video* device");
                NotificationService.notify("WEBCAM UNAVAILABLE", "no video capture device found");
                root._launch(root._webcamAudioDevice);
                return;
            }
            root._startWebcamOverlay(devices[0]);
        }
    }

    // Two-phase on Capture.webcamMapPollAction: wait up to 5s (widened from
    // upstream's own 2s client-detect loop, omarchy-capture-screenrecording:
    // 96-99, MIT -- too tight for real v4l2 init on some USB cameras) for
    // mpv's window to map, then a further 5s of reap-only watching after the
    // honest WEBCAM UNAVAILABLE notification fires and the recording
    // launches without it, so a window that maps just past the timeout gets
    // closed the moment it appears instead of leaking into the recording
    // untracked (mpv was already spawned by _startWebcamOverlay by the time
    // either bound is hit). Matches by app id: a freshly spawned window
    // carries no id this shell already knows, so identity has to come from
    // what mpv itself was told to call itself.
    Timer {
        id: webcamMapTimer
        interval: 50
        repeat: true
        onTriggered: {
            root._webcamAttempts++;
            const win = (CompositorService.windows || []).find(w => w.appId === root._webcamAppId);
            const action = Capture.webcamMapPollAction(!!win, root._webcamAttempts, root._webcamGaveUp,
                Capture.WEBCAM_MAP_GIVEUP_ATTEMPTS, Capture.WEBCAM_MAP_REAP_ATTEMPTS);
            if (action === "place") {
                webcamMapTimer.stop();
                root._webcamWindowId = win.id;
                root._webcamAttempts = 0;
                CompositorService.floatWindow(win.id);
                webcamSettleTimer.restart();
            } else if (action === "reap") {
                webcamMapTimer.stop();
                console.warn("RecordingService: webcam mapped after the timeout; closing the straggler");
                CompositorService.closeWindow(win.id);
                root._webcamGaveUp = false;
            } else if (action === "give-up") {
                root._webcamGaveUp = true;
                console.warn("RecordingService: webcam overlay unavailable: camera did not open in time");
                NotificationService.notify("WEBCAM UNAVAILABLE", "camera did not open in time");
                root._launch(root._webcamAudioDevice);
            } else if (action === "stop") {
                webcamMapTimer.stop();
                root._webcamGaveUp = false;
            }
        }
    }

    // Two-phase on the same clock: waits for `rect` to appear at all (proof
    // the float actually landed) before issuing the resize/move, then waits
    // for the reported size to actually match what was requested (proof the
    // placement itself landed) before letting the recording start -- the
    // poll this shell has in place of upstream's blind 600ms sleep.
    Timer {
        id: webcamSettleTimer
        interval: 50
        repeat: true
        onTriggered: {
            root._webcamAttempts++;
            const win = (CompositorService.windows || []).find(w => w.id === root._webcamWindowId);
            const rect = win ? win.rect : null;
            if (rect && !root._webcamPlaced) {
                root._webcamPlaced = true;
                root._webcamAttempts = 0;
                const t = root._webcamTarget;
                CompositorService.placeFloatingWindow(win.id, t.x, t.y, t.width, t.height);
                return;
            }
            if (rect && root._webcamPlaced) {
                const t = root._webcamTarget;
                if (Math.round(rect.width) === t.width && Math.round(rect.height) === t.height) {
                    webcamSettleTimer.stop();
                    root._launch(root._webcamAudioDevice);
                    return;
                }
            }
            if (root._webcamAttempts >= 40) {
                webcamSettleTimer.stop();
                console.warn("RecordingService: webcam overlay did not settle in time, recording anyway");
                NotificationService.notify("WEBCAM UNPLACED", "the camera did not settle in time");
                root._launch(root._webcamAudioDevice);
            }
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
            root._setupWebcam(setup.device);
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
            if (!root._sawExit && !root._stopping) {
                root._cleanupWebcam();
                root._fail("wf-recorder not found (failed to start)");
            }
        }

        onExited: exitCode => {
            root._sawExit = true;
            killTimer.stop();
            root._cleanupWebcam();
            root._releaseAudio();
            const saved = root._pendingPath;
            root._pendingPath = "";
            root._pendingGeometry = "";
            root._pendingOutput = "";
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
            root._finalize(saved);
        }
    }

    // finalize_recording's own three-step shape (probe video, probe audio,
    // one ffmpeg pass), chained the same way mkdirProc -> audioProc ->
    // recProc already are above.
    Process {
        id: finalizeProbeVideoProc

        stdout: StdioCollector {
            id: finalizeVideoOut
        }
        onExited: exitCode => {
            root._finalizeReencode = Capture.finalizeNeedsReencode(finalizeVideoOut.text);
            finalizeProbeAudioProc.command = ["ffprobe", "-v", "error", "-select_streams", "a",
                "-show_entries", "stream=codec_type", "-of", "csv=p=0", root._finalizeSource];
            finalizeProbeAudioProc.running = true;
        }
    }

    Process {
        id: finalizeProbeAudioProc

        stdout: StdioCollector {
            id: finalizeAudioOut
        }
        onExited: exitCode => {
            const hasAudio = Capture.finalizeHasAudio(finalizeAudioOut.text);
            root._finalizeProcessed = Capture.finalizeOutputPath(root._finalizeSource);
            finalizeProc.command = Capture.finalizeArgv(root._finalizeSource, root._finalizeProcessed, {
                reencode: root._finalizeReencode,
                hasAudio: hasAudio
            });
            finalizeProc.running = true;
        }
    }

    Process {
        id: finalizeProc

        stderr: StdioCollector {
            id: finalizeErr
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                finalizeCleanupProc.command = ["mv", root._finalizeProcessed, root._finalizeSource];
            } else {
                console.warn("RecordingService: finalize failed, keeping the raw recording:",
                    finalizeErr.text.trim() || ("ffmpeg exited " + exitCode));
                finalizeCleanupProc.command = ["rm", "-f", root._finalizeProcessed];
            }
            finalizeCleanupProc.running = true;
        }
    }

    // Reused for both the success move and the failure cleanup, the same
    // one-process-two-call-sites idiom unloadProc already establishes.
    Process {
        id: finalizeCleanupProc
        onExited: exitCode => root._announceSaved(root._finalizeSource)
    }

    // A failed grab still announces the save with no image rather than
    // holding the notification back -- a missing thumbnail is never a
    // reason to withhold a finished recording.
    Process {
        id: previewProc
        onExited: exitCode => {
            const path = root._previewSource;
            const preview = Capture.previewFramePath(path);
            const image = exitCode === 0 ? preview : "";
            NotificationService.notify("RECORDING SAVED", path, 1, [
                {
                    key: "default",
                    label: "PLAY",
                    invoke: () => root.play(path)
                },
                {
                    key: "gif",
                    label: "GIF",
                    invoke: () => root.gif(path)
                }
            ], image);
            if (image !== "") {
                root._previewCleanupPath = image;
                previewCleanupTimer.restart();
            }
        }
    }

    // 2s, matching upstream's own delay (omarchy-capture-screenrecording:
    // 236-239, MIT): Toasts.qml loads the image into memory once when the
    // popup appears and never re-reads the path, so the frame only has to
    // outlive that load, not the toast itself.
    Timer {
        id: previewCleanupTimer
        interval: 2000
        onTriggered: {
            previewCleanupProc.command = ["rm", "-f", root._previewCleanupPath];
            previewCleanupProc.running = true;
        }
    }

    Process {
        id: previewCleanupProc
    }

    Process {
        id: playerProc

        stderr: StdioCollector {
            id: playerErr
        }
        onExited: exitCode => {
            if (exitCode === 0)
                return;
            const why = playerErr.text.trim() || ("player exited " + exitCode);
            console.warn("RecordingService: player launch failed:", why);
            NotificationService.notify("PLAYER FAILED", why);
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

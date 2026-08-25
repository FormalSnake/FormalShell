import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Core as Core
import qs.Compositor
import qs.Services
import "../../Screensaver/effect.js" as Effect
import "../../Screensaver/ttfx.js" as Ttfx

// Idle-driven screensaver (DESIGN.md's terminal-text-effect exception, spec
// §10, M7 Task 5): one controller (this Item) decides WHEN to show, the
// session-wide IdleService.isIdle crossed with a live media-playback guard
//, and a Variants loop below spawns the actual per-output overlay
// surfaces. Mirrors Lock.qml's own "one controller, many surfaces" split:
// WlSessionLock manages its outputs internally so Lock.qml needs no
// explicit per-screen loop, but Quickshell has no equivalent auto-multi-
// output primitive for a plain overlay layer, so this does it explicitly
// over Quickshell.screens instead, with every delegate reading its shared
// `active` state straight off this outer Item (legal QML scoping, Lock.qml
// / LockSurface.qml's own `surface: Component { LockSurface { ... } }`
// already relies on exactly this to forward `root.authError` etc. into a
// Component declared inline).
Item {
    id: root

    // Forced true by an explicit `screensaver start` IPC call, independent
    // of IdleService entirely, the deterministic manual path a headless
    // smoke run (or a compositor keybind) can rely on without waiting on a
    // real idle timeout.
    property bool _forced: false

    // Set by stop() (IPC `screensaver stop`, or any real input on a
    // surface below) and held until IdleService.isIdle next drops to false
    //, i.e. until genuine activity actually happens, so a single
    // dismissal doesn't get instantly overridden by `_autoWant` still
    // reading true from the very same idle stretch, but also doesn't
    // suppress the NEXT idle cycle once real activity resets things.
    property bool _suppressed: false

    readonly property int lockAfterSeconds: Core.Config.get("screensaver.lockAfterSeconds", 0)
    readonly property bool guardMediaPlayback: Core.Config.get("screensaver.guardMediaPlayback", true)

    // ---- banner (DESIGN.md's "full-screen block-drawing ASCII banner ...
    // is the subject", M8b Task 7) ------------------------------------------

    // "" (the default) means the bundled banner; any other value is a path
    // to a user-supplied text file, our equivalent of omarchy's
    // omarchy-branding-screensaver replacement command.
    readonly property string _configuredAsciiPath: Core.Config.get("screensaver.asciiPath", "")
    readonly property string _bundledAsciiPath: Quickshell.shellPath("branding/screensaver.txt")
    property bool _customAsciiFailed: false
    readonly property string _asciiPath: (root._configuredAsciiPath.length > 0 && !root._customAsciiFailed) ? root._configuredAsciiPath : root._bundledAsciiPath
    property var _banner: Effect.parseBanner("")

    FileView {
        id: bannerFile
        path: root._asciiPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._banner = Effect.parseBanner(text())
        onLoadFailed: error => {
            if (root._configuredAsciiPath.length > 0 && !root._customAsciiFailed) {
                console.warn("Screensaver: failed to load screensaver.asciiPath (" + root._configuredAsciiPath + "), falling back to the bundled banner");
                root._customAsciiFailed = true;
            } else {
                console.warn("Screensaver: bundled banner failed to load at", root._bundledAsciiPath);
            }
        }
    }

    // ---- engine (ttfx, with effect.js as the no-binary fallback) -----------
    // ttfx is on PATH in every real install (nix/package.nix prefixes it onto
    // the wrapper), so `builtin` is what a bare `qs -p shell/` dev run, or an
    // install that skipped the wrapper, falls back to, rather than a blank
    // overlay. Probed once at shell startup, long before any activation, the
    // same way VisualizerService probes cava.

    property string _ttfxState: "unknown"
    readonly property string engine: root._ttfxState === "available" ? "ttfx" : "builtin"

    Process {
        id: ttfxProbe
        running: true
        command: ["sh", "-c", "command -v ttfx >/dev/null 2>&1"]
        onExited: exitCode => root._ttfxState = exitCode === 0 ? "available" : "missing"
    }

    // ---- effect selection (spec: "screensaver.effect accepts a name or
    // 'random', the default; each activation picks fresh") -----------------
    // Which pool "random" draws from follows the engine: ttfx's 37 effects,
    // or effect.js's five. A `screensaver.effect` naming an effect the active
    // engine doesn't have falls back to that engine's random pick, so a
    // config pinning `beams` still animates on a host with no ttfx.

    readonly property string _requestedEffect: Core.Config.get("screensaver.effect", "random")
    readonly property int frameRate: Core.Config.get("screensaver.frameRate", 60)
    property int _activationSeed: 0
    property bool _loggedUnknownEffect: false
    property string _previousEffect: ""
    readonly property string _effectiveEffect: root.engine === "ttfx"
        ? Ttfx.rerollEffectName(root._requestedEffect, root._previousEffect, root._activationSeed)
        : Effect.rerollEffectName(root._requestedEffect, root._previousEffect, root._activationSeed)

    // ---- continuous cycling (M13b Task 5): once an effect converges the
    // surfaces hold the finished banner for holdSeconds, then _reroll()
    // picks the next cycle ("random" never repeats the effect it just
    // showed; a pinned effect replays with a fresh frame counter) and every
    // surface restarts from frame 0, indefinitely until the screensaver
    // stops. Under ttfx an effect converging IS its process exiting, so the
    // hold runs off holdTimer below; under the builtin engine it's the same
    // per-surface auto timer that animates frames reaching _rerollAtFrame.
    // Either way a `frame(n)` pin suspends cycling, the M11 recorder keeps
    // capturing one single, deterministic effect. No idle inhibitor is taken
    // anywhere here, so system suspend fires exactly as it would over a
    // static banner. --------------------------------------------------------

    readonly property real holdSeconds: Core.Config.get("screensaver.holdSeconds", 6)
    readonly property int frameIntervalMs: 90
    property int cycles: 0
    readonly property int _rerollAtFrame: root.convergenceFrame() + Effect.holdFrames(root.holdSeconds, root.frameIntervalMs)
    signal cycleRestarted()

    // Called by a surface whose ttfx run ended. Restart, not start: several
    // outputs each end their own run a few milliseconds apart, and the hold
    // is one shared window before the next effect, not one per screen.
    function noteConverged() {
        if (root.active && root.engine === "ttfx" && root._pinnedFrame < 0)
            holdTimer.restart();
    }

    Timer {
        id: holdTimer
        interval: Math.max(1, root.holdSeconds * 1000)
        repeat: false
        onTriggered: root._reroll()
    }

    function _reroll() {
        root._previousEffect = root._effectiveEffect;
        root._activationSeed = Date.now();
        root.cycles += 1;
        root.cycleRestarted();
    }

    // ---- deterministic frame stepping (ScreensaverIpc's `frame(n)`, M11
    // Task 1), a verification affordance only, never how the screensaver
    // normally animates: -1 (the default) means "not pinned", so every
    // surface below free-runs its own Timer-driven counter exactly as
    // before. Released the instant `active` goes false (see onActiveChanged
    // below) so a recorder can never leave a stale pin behind for the next
    // real activation. --------------------------------------------------

    property int _pinnedFrame: -1

    // Frames counted in the last completed pinned ttfx run, 0 until one has
    // finished, which is why a recorder pins frame 0 first and reads
    // frameInfo after. Under ttfx there is no closed-form convergence frame
    // to compute the way effect.js has one: the only honest answer is how
    // many frames the effect actually produced, capped at
    // Ttfx.PIN_FRAME_CAP.
    property int _ttfxFrameCount: 0

    readonly property string effectName: root._effectiveEffect

    function convergenceFrame() {
        if (root.engine === "ttfx")
            return root._ttfxFrameCount;
        return Effect.convergenceFrame(root._effectiveEffect, root._banner);
    }

    function pinFrame(n) {
        // A hold already counting down when the recorder pins would reroll
        // mid-capture, swapping the effect (and the seed) halfway through a
        // GIF. Pinning ends the cycle loop until the pin is released.
        holdTimer.stop();
        root._pinnedFrame = n;
    }

    // Live, not edge-triggered: recomputes continuously off IdleService and
    // MediaService, so a track starting or ending mid-idle-stretch flips
    // this immediately either way, spec §10's "never activates while ...
    // media is actually playing" is a standing condition, not a one-time
    // check made only at the moment idle first fires. IdleService.stayAwake
    // (M-polish batch item B) holds the whole idle chain exactly like the
    // media guard, lockAfterSeconds' own auto-lock timer only ever runs
    // while `active` is true, so gating activation here is enough to hold
    // that chain too, with no separate check needed there.
    readonly property bool _autoWant: IdleService.isIdle && !root._suppressed
        && (!root.guardMediaPlayback || !MediaService.isPlaying)
        && !IdleService.stayAwake

    readonly property bool active: root._forced || root._autoWant

    function start() {
        root._forced = true;
    }

    function stop() {
        root._forced = false;
        root._suppressed = true;
    }

    // Real activity clears a stale suppression the instant the compositor
    // reports genuine non-idle input, otherwise one dismissal would
    // permanently disable the auto-trigger for the rest of the session.
    Connections {
        target: IdleService
        function onIsIdleChanged() {
            if (!IdleService.isIdle)
                root._suppressed = false;
        }
    }

    onActiveChanged: {
        // Either direction cancels a hold in flight. A hold is the gap
        // between one converged effect and the next, and it belongs to the
        // activation that started it: left running across a stop, it fires
        // inside the NEXT activation and rerolls an effect that has barely
        // begun, with the fresh activation's own `cycles: 0` already
        // counted past. Observed as a smoke failure (frameInfo reporting
        // cycles:1 one second after a manual start, 2026-08-12).
        holdTimer.stop();
        if (root.active) {
            // Fresh, not kept: focus moves freely while the session is awake,
            // so the previous activation's answer says nothing about which
            // screen was being used before this one.
            root._resolveMainOutput(false);
            // A fresh seed per activation is what makes "random" (the
            // default) actually vary across activations instead of picking
            // once at shell startup and sticking forever. The previous-
            // effect exclusion and cycle counter reset with it: each
            // activation starts an unconstrained cycle 0.
            root._previousEffect = "";
            root.cycles = 0;
            root._ttfxFrameCount = 0;
            root._activationSeed = Date.now();
            var known = root.engine === "ttfx" ? Ttfx.isKnownEffect(root._requestedEffect) : Effect.isKnownEffect(root._requestedEffect);
            if (root._requestedEffect !== "random" && !known && !root._loggedUnknownEffect) {
                console.warn("Screensaver: unknown screensaver.effect '" + root._requestedEffect + "', falling back to random");
                root._loggedUnknownEffect = true;
            }
        } else {
            // Any deactivation path (explicit stop(), the media guard
            // clearing, real input) releases a stale frame pin so the next
            // activation always free-runs normally.
            root._pinnedFrame = Effect.nextPinnedFrame(root.active, root._pinnedFrame);
        }
        if (root.active && root.lockAfterSeconds > 0)
            lockChainTimer.restart();
        else
            lockChainTimer.stop();
    }

    // ---- main output (MainOutputService) ----------------------------------
    // The one screen that animates is the shell's main output:
    // `display.outputPriority`'s first entry with a screen actually
    // connected, e.g. ["HDMI", "internal"] for "the desk monitor while it's
    // plugged in". With the key unset it's the focused output, resolved at
    // activation rather than bound live, a focus event landing mid-run
    // would restart ttfx on two screens at once, and nothing can move focus
    // while the session is idle anyway.

    property string mainOutput: ""

    function _resolveMainOutput(keepCurrent) {
        root.mainOutput = root.previewMainOutput(keepCurrent);
    }

    // The same answer without becoming it, so a multi-head host can be
    // checked over `screensaver status` with a read instead of by putting a
    // full-screen surface over a live session.
    function previewMainOutput(keepCurrent) {
        return MainOutputService.resolve(keepCurrent ? root.mainOutput : "");
    }

    // Bound rather than connected so this re-runs off screensChanged itself.
    // Both directions matter: unplugging the animating screen leaves nothing
    // animating at all without this, and plugging the priority list's first
    // choice back in is meant to hand the animation over to it.
    readonly property var _screens: Quickshell.screens
    on_ScreensChanged: {
        if (root.active)
            root._resolveMainOutput(true);
    }

    // Optional chain into Lock after continued inactivity once already
    // showing (spec §10), 0 (the default) disables the chain outright,
    // since most deployments (and every reader-less VM) have no reason to
    // want it on unasked.
    Timer {
        id: lockChainTimer
        interval: root.lockAfterSeconds * 1000
        running: false
        repeat: false
        onTriggered: {
            if (root.active)
                LockService.lock();
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: surface
                required property var modelData
                screen: modelData
                // Held mapped through the exit fade (DESIGN.md §4 rule 6),
                // same as Panel.qml's frame: `active` drops, content's
                // opacity Behavior runs to 0, and only then does the window
                // unmap. Everything below therefore keys off `root.active`
                // rather than `surface.visible`, for the length of the fade
                // the two disagree, and activation is the one that means
                // "this screensaver is running".
                visible: root.active || content.opacity > 0
                color: Core.Theme.color.background

                WlrLayershell.namespace: "formalshell:screensaver"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

                anchors { top: true; bottom: true; left: true; right: true }

                // Off-screen glyphs measured at the live mono font so the
                // banner's cell size reflects real metrics rather than a
                // guessed constant, same technique Osd.qml's own calibration
                // Text items use. Ten cells, not one, so per-glyph side
                // bearing amortizes into a true advance: every run this
                // surface paints is positioned at col * _cellWidth, and a
                // fraction of a pixel of error per cell would smear a
                // 96-column canvas by tens of pixels.
                Text {
                    id: metric
                    visible: false
                    text: "MMMMMMMMMM"
                    font.family: Core.Theme.fontFamilyMono
                    font.pixelSize: 100
                }

                readonly property real _advanceRatio: metric.implicitWidth / 1000
                readonly property real _lineRatio: metric.implicitHeight / 100

                // The banner is the entire subject of this surface (spec), so
                // it is scaled well past body size, but never past the point
                // where it stops fitting the screen. Before this clamp a
                // 1276px-wide session rendered the bundled 64-column banner as
                // "ORMALSHEL" (docs/screenshots/screensaver-niri.png, pre-M22),
                // and ttfx would truncate its canvas identically. +4 columns
                // keeps a little air at both edges.
                readonly property real _fitFontSize: (root._banner.width > 0 && surface._advanceRatio > 0)
                    ? surface.width / ((root._banner.width + 4) * surface._advanceRatio)
                    : Core.Theme.fontSize.body * 2.4
                readonly property real _fontSize: Math.max(8, Math.min(Core.Theme.fontSize.body * 2.4, surface._fitFontSize))
                readonly property real _cellWidth: Math.max(1, surface._fontSize * surface._advanceRatio)
                readonly property real _cellHeight: Math.max(1, surface._fontSize * surface._lineRatio * 1.15)
                readonly property int _columns: surface.visible ? Math.max(1, Math.floor(width / surface._cellWidth)) : 0
                readonly property int _rows: surface.visible ? Math.max(1, Math.floor(height / surface._cellHeight)) : 0

                // Only the main output animates (outputs.js); every other
                // screen stays a bare background field. "" means the resolver
                // found no outputs to choose between, which can only happen
                // with none connected, animating then costs nothing and is
                // the safer way to be wrong.
                readonly property bool animated: root.mainOutput === "" || surface.modelData.name === root.mainOutput
                onAnimatedChanged: {
                    surface._grid = [];
                    surface._startRun();
                    canvas.requestPaint();
                }

                // ---- ttfx engine ---------------------------------------
                // One process for the animating output. Its canvas is
                // measured in that screen's own cells, so this stays inside
                // the delegate rather than being hoisted to root, the
                // surface that animates is decided per activation, and a
                // hotplug can hand the run to a differently-sized screen.
                // The effect name, seed and cycle counter all come from root.

                property var _grid: []          // parsed rows of the frame on screen
                property int _chunks: 0         // stdout segments seen this run
                property int _runFrames: 0      // animation frames seen this run

                // Terminating a Process to restart it is asynchronous: the
                // old QProcess is still alive when `running` goes back to
                // true, so quickshell defers the new run until it reaps the
                // old one (Process::onFinished -> startProcessIfReady). One
                // stale `exited`, and one stale stdout flush before it,
                // therefore arrives per restart, and neither belongs to the
                // run now on screen. Counted rather than flagged: two
                // restarts in the same tick owe two stale exits.
                property int _staleExits: 0

                // Becoming visible changes visibility, columns and rows in
                // the same turn, and each of those wants the run restarted,
                // Qt.callLater collapses them into the single start that
                // actually happens, instead of spawning ttfx three times and
                // killing two of them.
                function _startRun() {
                    Qt.callLater(surface._applyRun);
                }

                function _applyRun() {
                    if (ttfxProc.running)
                        surface._staleExits += 1;
                    ttfxProc.running = false;
                    surface._chunks = 0;
                    surface._runFrames = 0;
                    if (root.engine !== "ttfx" || !root.active || !surface.animated || surface._columns <= 0 || surface._rows <= 0)
                        return;
                    // A pinned run regenerates the effect from frame 0 and
                    // races to the requested frame with pacing disabled,
                    // ttfx is deterministic under a fixed seed, so stepping
                    // by re-running costs a few tens of milliseconds and
                    // needs no frame buffer at all.
                    var pinned = root._pinnedFrame >= 0;
                    ttfxProc.command = Ttfx.command({
                        bannerPath: root._asciiPath,
                        columns: surface._columns,
                        rows: surface._rows,
                        effect: root._effectiveEffect,
                        frameRate: pinned ? 0 : root.frameRate,
                        background: String(Core.Theme.color.background),
                        seed: root._activationSeed + root.cycles
                    });
                    frameParser.splitMarker = Ttfx.frameDelimiter(surface._rows);
                    ttfxProc.running = true;
                }

                function _onChunk(chunk) {
                    if (surface._staleExits > 0)
                        return;
                    // The first segment is ttfx's canvas prep (hide cursor,
                    // then the blank canvas it will animate over), not a
                    // frame, painting it would just clear the surface, which
                    // it already is.
                    var index = surface._chunks;
                    surface._chunks += 1;
                    if (index === 0)
                        return;
                    surface._runFrames = index;

                    if (root._pinnedFrame >= 0) {
                        if (index - 1 === root._pinnedFrame) {
                            surface._grid = Ttfx.parseFrame(chunk);
                            canvas.requestPaint();
                        }
                        if (index >= Ttfx.PIN_FRAME_CAP) {
                            // Capped, not ended: record what was counted and
                            // own the exit this kill produces, so it can't
                            // read as the run finishing on its own.
                            root._ttfxFrameCount = surface._runFrames;
                            surface._staleExits += 1;
                            ttfxProc.running = false;
                        }
                        return;
                    }
                    surface._grid = Ttfx.parseFrame(chunk);
                    canvas.requestPaint();
                }

                Process {
                    id: ttfxProc
                    stdout: SplitParser {
                        id: frameParser
                        onRead: chunk => surface._onChunk(chunk)
                    }
                    onExited: exitCode => {
                        if (surface._staleExits > 0) {
                            surface._staleExits -= 1;
                            return;
                        }
                        if (exitCode !== 0) {
                            // 127 is ttfx gone from PATH since the startup
                            // probe; anything else is a run this shell asked
                            // for and ttfx refused. Either way, fall back to
                            // the builtin engine rather than leave the
                            // surface blank, and rather than respawn, which
                            // for a rejected argv would spin.
                            console.warn("Screensaver: ttfx exited " + exitCode + ", falling back to the builtin effects");
                            root._ttfxState = "missing";
                            return;
                        }
                        if (root._pinnedFrame >= 0) {
                            root._ttfxFrameCount = surface._runFrames;
                            return;
                        }
                        root.noteConverged();
                    }
                }

                // A resize (this screen's mode, or a font-size change)
                // re-measures the canvas, which ttfx can only be told about
                // by restarting it.
                on_ColumnsChanged: surface._startRun()
                on_RowsChanged: surface._startRun()

                // Free-running counter for the ordinary, non-pinned path,
                // untouched by frame stepping. _renderFrame is what
                // everything below actually paints: root's pin (when set)
                // wins outright, otherwise it's this counter.
                property int _autoFrame: 0
                readonly property int _renderFrame: Effect.resolveRenderFrame(root._pinnedFrame, surface._autoFrame)
                on_RenderFrameChanged: canvas.requestPaint()

                Timer {
                    interval: root.frameIntervalMs
                    running: root.engine === "builtin" && surface.animated && Effect.autoTimerShouldRun(root.active, root._pinnedFrame)
                    repeat: true
                    onTriggered: {
                        surface._autoFrame += 1;
                        canvas.requestPaint();
                        // >= rather than ===: a mid-cycle banner reload can
                        // shrink the threshold below an already-past counter,
                        // and the cycle must still advance rather than stall.
                        // cycleRestarted resets every surface synchronously,
                        // so a second surface's own tick can never double-fire
                        // the same reroll.
                        if (surface._autoFrame >= root._rerollAtFrame)
                            root._reroll();
                    }
                }

                Connections {
                    target: root
                    // Activation, not mapping, starts and stops a run: the
                    // window stays mapped through the exit fade below, and a
                    // run left animating behind a fading surface would hold a
                    // ttfx process per output open for the length of it.
                    function onActiveChanged() {
                        if (root.active) {
                            // Every activation replays its effect from
                            // scratch, without this a long-idle session that
                            // already ran the animation past its convergence
                            // frame would just show the static finished
                            // banner on the very next activation instead of
                            // animating. The grid goes with it, so the fade
                            // in starts on an empty canvas rather than on the
                            // last frame of the previous activation.
                            surface._autoFrame = 0;
                            surface._grid = [];
                            canvas.requestPaint();
                            Qt.callLater(function () { dismissArea.forceActiveFocus(); });
                            // Becoming visible/mapped underneath an already-
                            // stationary cursor fires MouseArea's own first
                            // positionChanged with no real movement behind it
                            // (reproduced on the mac VM rig, 2026-07-28: the
                            // very first auto-activation dismissed itself
                            // instantly this way), dropping any baseline
                            // here makes dismissArea treat that first report
                            // as a reference point instead of real activity.
                            dismissArea._hasBaseline = false;
                        }
                        // Through _startRun, not a bare `running = false`, so
                        // a stop is accounted for the same way a restart is
                        // and the exit it produces can't read as convergence.
                        surface._startRun();
                    }
                    function onCycleRestarted() {
                        surface._autoFrame = 0;
                        surface._grid = [];
                        surface._startRun();
                    }
                    // Frame stepping restarts the ttfx run from frame 0 and
                    // races to the requested frame; the builtin engine just
                    // renders _renderFrame straight out of effect.js.
                    function on_PinnedFrameChanged() {
                        if (root.engine === "ttfx")
                            surface._startRun();
                    }
                    function onEngineChanged() {
                        surface._startRun();
                    }
                    // Watched on the banner file, so it can land mid-run,
                    // and a paint-once surface has no next frame to pick the
                    // new text up on.
                    function on_BannerChanged() {
                        canvas.requestPaint();
                    }
                }

                // Fades both ways (DESIGN.md §4 rule 6, owner's call
                // 2026-08-12), opacity only, a full-screen surface has no
                // edge to slide in from. At `reveal` rather than `standard`,
                // the same 400ms the wallpaper crossfade already uses: a
                // full-screen swap paced at 130ms reads as a flash, not a
                // fade. `motion.enabled: false` zeroes `reveal` too, so a
                // reduced-motion session still gets the old hard cut in both
                // directions. Lives on an inner Item, not `surface` itself,
                // PanelWindow has no Item-style `opacity` of its own
                // (Panel.qml/Menu.qml's frame/card carry their own fades the
                // same way), and `surface.visible` above holds the window
                // mapped until this reaches 0.
                Item {
                    id: content
                    anchors.fill: parent
                    opacity: root.active ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: Core.Theme.motion.reveal; easing.type: Core.Theme.motion.easing }
                    }

                    Canvas {
                        id: canvas
                        anchors.fill: parent
                        renderStrategy: Canvas.Cooperative

                        // A Canvas repaints on resize, never on a change to
                        // something its paint happens to read. Frames repaint
                        // themselves, but the converged banner sits still for
                        // holdSeconds before the next cycle, and a recolor
                        // landing in that window would hold the old palette
                        // until it expired (a `wallpaper set` over IPC lands
                        // mid-idle with no input to dismiss the screensaver
                        // first).
                        readonly property color _accent: Core.Theme.color.primary
                        readonly property color _background: Core.Theme.color.background
                        on_AccentChanged: canvas.requestPaint()
                        on_BackgroundChanged: canvas.requestPaint()

                        onPaint: {
                            var ctx = canvas.getContext("2d");
                            ctx.fillStyle = Core.Theme.color.background;
                            ctx.fillRect(0, 0, width, height);
                            // Only the main output carries the effect;
                            // every other screen is left as a bare
                            // background field (owner's call,
                            // 2026-08-21).
                            if (!surface.animated)
                                return;
                            var banner = root._banner;
                            if (surface._columns <= 0 || surface._rows <= 0 || banner.width <= 0)
                                return;
                            ctx.font = surface._fontSize + "px " + Core.Theme.fontFamilyMono;
                            ctx.textBaseline = "top";
                            var offsetCol = Math.floor((surface._columns - banner.width) / 2);
                            var offsetRow = Math.floor((surface._rows - banner.height) / 2);

                            // ttfx owns the whole canvas, colors included:
                            // each effect paints in its own upstream gradient
                            // (omarchy passes no gradient overrides either),
                            // and anything it leaves uncolored falls back to
                            // the theme's foreground rather than a guess.
                            if (root.engine === "ttfx") {
                                var rows = surface._grid;
                                for (var gr = 0; gr < rows.length; gr++) {
                                    var runs = rows[gr];
                                    for (var i = 0; i < runs.length; i++) {
                                        var run = runs[i];
                                        ctx.fillStyle = run.color.length > 0 ? run.color : Core.Theme.color.foreground;
                                        ctx.fillText(run.text, run.col * surface._cellWidth, gr * surface._cellHeight);
                                    }
                                }
                                return;
                            }

                            var grid = Effect.frameState(root._effectiveEffect, surface._renderFrame, banner);
                            for (var r = 0; r < grid.length; r++) {
                                var rowCells = grid[r];
                                for (var c = 0; c < rowCells.length; c++) {
                                    var cell = rowCells[c];
                                    if (cell.opacity <= 0)
                                        continue;
                                    ctx.globalAlpha = cell.opacity;
                                    ctx.fillStyle = Core.Theme.color.primary;
                                    ctx.fillText(cell.char, (offsetCol + c) * surface._cellWidth, (offsetRow + r) * surface._cellHeight);
                                }
                            }
                            ctx.globalAlpha = 1;
                        }
                    }

                    // Any input dismisses it (spec §10): hover-tracks pointer
                    // movement and key presses, both calling the same stop()
                    // path ScreensaverIpc's own explicit verb uses. The first
                    // position report after becoming visible is recorded as a
                    // baseline rather than treated as activity, see
                    // onVisibleChanged above for why that first report can't be
                    // trusted as real movement.
                    MouseArea {
                        id: dismissArea
                        anchors.fill: parent
                        hoverEnabled: true
                        focus: surface.visible
                        property bool _hasBaseline: false
                        property real _lastX: 0
                        property real _lastY: 0
                        Keys.onPressed: root.stop()
                        onPositionChanged: mouse => {
                            if (!dismissArea._hasBaseline) {
                                dismissArea._hasBaseline = true;
                                dismissArea._lastX = mouse.x;
                                dismissArea._lastY = mouse.y;
                                return;
                            }
                            if (mouse.x === dismissArea._lastX && mouse.y === dismissArea._lastY)
                                return;
                            dismissArea._lastX = mouse.x;
                            dismissArea._lastY = mouse.y;
                            root.stop();
                        }
                        onClicked: root.stop()
                    }
                }
            }
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Core as Core
import qs.Services
import "../../Screensaver/effect.js" as Effect

// Idle-driven screensaver (DESIGN.md's terminal-text-effect exception, spec
// §10, M7 Task 5): one controller (this Item) decides WHEN to show — the
// session-wide IdleService.isIdle crossed with a live media-playback guard
// — and a Variants loop below spawns the actual per-output overlay
// surfaces. Mirrors Lock.qml's own "one controller, many surfaces" split:
// WlSessionLock manages its outputs internally so Lock.qml needs no
// explicit per-screen loop, but Quickshell has no equivalent auto-multi-
// output primitive for a plain overlay layer, so this does it explicitly
// over Quickshell.screens instead, with every delegate reading its shared
// `active` state straight off this outer Item (legal QML scoping — Lock.qml
// / LockSurface.qml's own `surface: Component { LockSurface { ... } }`
// already relies on exactly this to forward `root.authError` etc. into a
// Component declared inline).
Item {
    id: root

    // Forced true by an explicit `screensaver start` IPC call, independent
    // of IdleService entirely — the deterministic manual path a headless
    // smoke run (or a compositor keybind) can rely on without waiting on a
    // real idle timeout.
    property bool _forced: false

    // Set by stop() (IPC `screensaver stop`, or any real input on a
    // surface below) and held until IdleService.isIdle next drops to false
    // — i.e. until genuine activity actually happens — so a single
    // dismissal doesn't get instantly overridden by `_autoWant` still
    // reading true from the very same idle stretch, but also doesn't
    // suppress the NEXT idle cycle once real activity resets things.
    property bool _suppressed: false

    // Wired from shell.qml — the single Lock instance, same convention as
    // CalendarPanel's `menu` property. null (the default) leaves the
    // optional chain-into-lock inert.
    property var lockScreen: null

    readonly property int lockAfterSeconds: Core.Config.get("screensaver.lockAfterSeconds", 0)
    readonly property bool guardMediaPlayback: Core.Config.get("screensaver.guardMediaPlayback", true)

    // ---- banner (DESIGN.md's "full-screen block-drawing ASCII banner ...
    // is the subject", M8b Task 7) ------------------------------------------

    // "" (the default) means the bundled banner; any other value is a path
    // to a user-supplied text file — our equivalent of omarchy's
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

    // ---- effect selection (spec: "screensaver.effect accepts a name or
    // 'random' — the default; each activation picks fresh") -----------------

    readonly property string _requestedEffect: Core.Config.get("screensaver.effect", "random")
    property int _activationSeed: 0
    property bool _loggedUnknownEffect: false
    property string _previousEffect: ""
    readonly property string _effectiveEffect: Effect.rerollEffectName(root._requestedEffect, root._previousEffect, root._activationSeed)

    // ---- continuous cycling (M13b Task 5): once an effect converges the
    // surfaces hold the finished banner for holdSeconds, then _reroll()
    // picks the next cycle ("random" never repeats the effect it just
    // showed; a pinned effect replays with a fresh frame counter) and every
    // surface restarts from frame 0, indefinitely until the screensaver
    // stops. The loop is driven by the same per-surface auto timer that
    // animates frames, so a `frame(n)` pin (which stops that timer) also
    // suspends cycling — the M11 recorder keeps capturing one single,
    // deterministic effect. No idle inhibitor is taken anywhere here, so
    // system suspend fires exactly as it would over a static banner. ------

    readonly property real holdSeconds: Core.Config.get("screensaver.holdSeconds", 6)
    readonly property int frameIntervalMs: 90
    property int cycles: 0
    readonly property int _rerollAtFrame: root.convergenceFrame() + Effect.holdFrames(root.holdSeconds, root.frameIntervalMs)
    signal cycleRestarted()

    function _reroll() {
        root._previousEffect = root._effectiveEffect;
        root._activationSeed = Date.now();
        root.cycles += 1;
        root.cycleRestarted();
    }

    // ---- deterministic frame stepping (ScreensaverIpc's `frame(n)`, M11
    // Task 1) — a verification affordance only, never how the screensaver
    // normally animates: -1 (the default) means "not pinned", so every
    // surface below free-runs its own Timer-driven counter exactly as
    // before. Released the instant `active` goes false (see onActiveChanged
    // below) so a recorder can never leave a stale pin behind for the next
    // real activation. --------------------------------------------------

    property int _pinnedFrame: -1

    readonly property string effectName: root._effectiveEffect

    function convergenceFrame() {
        return Effect.convergenceFrame(root._effectiveEffect, root._banner);
    }

    function pinFrame(n) {
        root._pinnedFrame = n;
    }

    // Live, not edge-triggered: recomputes continuously off IdleService and
    // MediaService, so a track starting or ending mid-idle-stretch flips
    // this immediately either way — spec §10's "never activates while ...
    // media is actually playing" is a standing condition, not a one-time
    // check made only at the moment idle first fires. IdleService.stayAwake
    // (M-polish batch item B) holds the whole idle chain exactly like the
    // media guard — lockAfterSeconds' own auto-lock timer only ever runs
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
    // reports genuine non-idle input — otherwise one dismissal would
    // permanently disable the auto-trigger for the rest of the session.
    Connections {
        target: IdleService
        function onIsIdleChanged() {
            if (!IdleService.isIdle)
                root._suppressed = false;
        }
    }

    onActiveChanged: {
        if (root.active) {
            // A fresh seed per activation is what makes "random" (the
            // default) actually vary across activations instead of picking
            // once at shell startup and sticking forever. The previous-
            // effect exclusion and cycle counter reset with it: each
            // activation starts an unconstrained cycle 0.
            root._previousEffect = "";
            root.cycles = 0;
            root._activationSeed = Date.now();
            if (root._requestedEffect !== "random" && !Effect.isKnownEffect(root._requestedEffect) && !root._loggedUnknownEffect) {
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

    // Optional chain into Lock after continued inactivity once already
    // showing (spec §10) — 0 (the default) disables the chain outright,
    // since most deployments (and every reader-less VM) have no reason to
    // want it on unasked.
    Timer {
        id: lockChainTimer
        interval: root.lockAfterSeconds * 1000
        running: false
        repeat: false
        onTriggered: {
            if (root.active && root.lockScreen)
                root.lockScreen.lock();
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: surface
                required property var modelData
                screen: modelData
                visible: root.active
                color: Core.Theme.color.background

                WlrLayershell.namespace: "formalshell:screensaver"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: surface.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

                anchors { top: true; bottom: true; left: true; right: true }

                onVisibleChanged: {
                    if (surface.visible) {
                        // Every activation replays its effect from scratch
                        // — without this a long-idle session that already
                        // ran the animation past its convergence frame
                        // would just show the static finished banner on
                        // the very next activation instead of animating.
                        surface._autoFrame = 0;
                        Qt.callLater(function () { dismissArea.forceActiveFocus(); });
                        // Becoming visible/mapped underneath an already-
                        // stationary cursor fires MouseArea's own first
                        // positionChanged with no real movement behind it
                        // (reproduced on the mac VM rig, 2026-07-28: the
                        // very first auto-activation dismissed itself
                        // instantly this way) — dropping any baseline here
                        // makes dismissArea treat that first report as a
                        // reference point instead of real activity.
                        dismissArea._hasBaseline = false;
                        // Imperative, not `opacity: surface.visible ? 1 : 0`
                        // with a `Behavior … { enabled: surface.visible }`
                        // guard: QML evaluates that opacity binding before
                        // the Behavior's own `enabled` binding reacts to the
                        // same `visible` change, so the guard is still false
                        // when the write lands and the fade never runs.
                        // Driving opacity from here sidesteps the ordering
                        // race — the Behavior stays unconditionally enabled.
                        content.opacity = 1;
                    } else {
                        content.opacity = 0;
                    }
                }

                // Off-screen glyph measured once at the live mono font so
                // the banner's cell size reflects real metrics rather than
                // a guessed constant — same technique Osd.qml's own
                // calibration Text items use. Scaled well past body size:
                // the banner is the entire subject of this surface (spec),
                // not a line of text within it.
                Text {
                    id: metric
                    visible: false
                    text: "M"
                    font.family: Core.Theme.fontFamily
                    font.pixelSize: Core.Theme.fontSize.body * 2.4
                }

                readonly property int _cellWidth: Math.max(1, Math.ceil(metric.implicitWidth))
                readonly property int _cellHeight: Math.max(1, Math.ceil(metric.implicitHeight * 1.15))
                readonly property int _columns: surface.visible ? Math.max(1, Math.floor(width / surface._cellWidth)) : 0
                readonly property int _rows: surface.visible ? Math.max(1, Math.floor(height / surface._cellHeight)) : 0

                // Free-running counter for the ordinary, non-pinned path —
                // untouched by frame stepping. _renderFrame is what
                // everything below actually paints: root's pin (when set)
                // wins outright, otherwise it's this counter.
                property int _autoFrame: 0
                readonly property int _renderFrame: Effect.resolveRenderFrame(root._pinnedFrame, surface._autoFrame)
                on_RenderFrameChanged: canvas.requestPaint()

                Timer {
                    interval: root.frameIntervalMs
                    running: Effect.autoTimerShouldRun(surface.visible, root._pinnedFrame)
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
                    function onCycleRestarted() {
                        surface._autoFrame = 0;
                    }
                }

                // Enter fades in (DESIGN.md §4/§3), opacity only — a
                // full-screen surface has no edge to slide in from; exit
                // reads as instant regardless, since `surface.visible`
                // above unmaps the whole window the moment it drops.
                // Driven imperatively from `onVisibleChanged` above, not a
                // `surface.visible ? 1 : 0` binding — see that handler's
                // comment for why. Lives on an inner Item, not `surface`
                // itself — PanelWindow has no Item-style `opacity` of its
                // own (Panel.qml/Menu.qml's frame/card carry their own
                // fades the same way).
                Item {
                    id: content
                    anchors.fill: parent
                    opacity: 0

                    Behavior on opacity {
                        NumberAnimation { duration: Core.Theme.motion.standard; easing.type: Core.Theme.motion.easing }
                    }

                    Canvas {
                        id: canvas
                        anchors.fill: parent
                        renderStrategy: Canvas.Cooperative

                        onPaint: {
                            var ctx = canvas.getContext("2d");
                            ctx.fillStyle = Core.Theme.color.background;
                            ctx.fillRect(0, 0, width, height);
                            var banner = root._banner;
                            if (surface._columns <= 0 || surface._rows <= 0 || banner.width <= 0)
                                return;
                            ctx.font = surface._cellHeight + "px " + Core.Theme.fontFamily;
                            ctx.textBaseline = "top";
                            var offsetCol = Math.floor((surface._columns - banner.width) / 2);
                            var offsetRow = Math.floor((surface._rows - banner.height) / 2);
                            var grid = Effect.frameState(root._effectiveEffect, surface._renderFrame, banner);
                            for (var r = 0; r < grid.length; r++) {
                                var rowCells = grid[r];
                                for (var c = 0; c < rowCells.length; c++) {
                                    var cell = rowCells[c];
                                    if (cell.opacity <= 0)
                                        continue;
                                    ctx.globalAlpha = cell.opacity;
                                    ctx.fillStyle = Core.Theme.color.accent;
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
                    // baseline rather than treated as activity — see
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

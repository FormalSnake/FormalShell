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
    readonly property string _effectiveEffect: Effect.resolveEffectName(root._requestedEffect, root._activationSeed)

    // Live, not edge-triggered: recomputes continuously off IdleService and
    // MediaService, so a track starting or ending mid-idle-stretch flips
    // this immediately either way — spec §10's "never activates while ...
    // media is actually playing" is a standing condition, not a one-time
    // check made only at the moment idle first fires.
    readonly property bool _autoWant: IdleService.isIdle && !root._suppressed
        && (!root.guardMediaPlayback || !MediaService.isPlaying)

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
            // default) actually cycle across a long idle session instead
            // of picking once at shell startup and sticking forever.
            root._activationSeed = Date.now();
            if (root._requestedEffect !== "random" && !Effect.isKnownEffect(root._requestedEffect) && !root._loggedUnknownEffect) {
                console.warn("Screensaver: unknown screensaver.effect '" + root._requestedEffect + "', falling back to random");
                root._loggedUnknownEffect = true;
            }
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
                        surface._frame = 0;
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
                    font.family: Core.Theme.font.family
                    font.pixelSize: Core.Theme.font.body * 2.4
                }

                readonly property int _cellWidth: Math.max(1, Math.ceil(metric.implicitWidth))
                readonly property int _cellHeight: Math.max(1, Math.ceil(metric.implicitHeight * 1.15))
                readonly property int _columns: surface.visible ? Math.max(1, Math.floor(width / surface._cellWidth)) : 0
                readonly property int _rows: surface.visible ? Math.max(1, Math.floor(height / surface._cellHeight)) : 0

                property int _frame: 0

                Timer {
                    interval: 90
                    running: surface.visible
                    repeat: true
                    onTriggered: {
                        surface._frame += 1;
                        canvas.requestPaint();
                    }
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
                        ctx.font = surface._cellHeight + "px " + Core.Theme.font.family;
                        ctx.textBaseline = "top";
                        var offsetCol = Math.floor((surface._columns - banner.width) / 2);
                        var offsetRow = Math.floor((surface._rows - banner.height) / 2);
                        var grid = Effect.frameState(root._effectiveEffect, surface._frame, banner);
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

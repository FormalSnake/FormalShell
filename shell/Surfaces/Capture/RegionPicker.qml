import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Core as Core
import qs.Components
import qs.Compositor

// Region picker for the capture flow (M22 Tasks 5-7), a port in intent of
// omarchy quattro's `bin/omarchy-capture-region` rather than in code: the
// keyboard layer upstream added in August 2026 moves the selection by WARPING
// THE CURSOR so slurp's own hover highlight follows it, and binds its keys
// from Hyprland Lua reacting to `layer.opened` on slurp's `selection`
// namespace. The shell cannot inject binds into a compositor at runtime, so
// the picker is its own Overlay surface, which owns its highlight state
// directly: no warping, no compositor binds. Every
// probe-for-a-reachable-warp-point mechanism upstream had to invent exists
// only to steer a picker that does not know what is selected, and has no
// counterpart here.
//
// A window whose rect is null cannot be drawn and cannot be captured: there
// is no crop box and no server-side per-window capture to fall back on. Those
// windows are still NAMED, in a labelled list (title over dim app id) that
// says so, rather than vanishing from a mode that lists their neighbours.
// Hyprland reports a box for every window it does not hide, so the list is
// normally empty; an unfocused member of a tabbed group is the case that
// fills it (HyprlandBackend's `hasRect`).
//
// The freeze is upstream's trick, kept: grim captures each output BEFORE the
// surface maps, the surface renders those frames 1:1, and the capture then
// grims the surface itself with the chrome hidden for a frame. Content cannot
// shift mid-pick, and the overlay cannot photograph its own scrim. No
// ScreencopyView is involved anywhere (LockSurface.qml's header: it crashes
// the shell outright).
//
// THE TOOLBAR (owner ask, 2026-08-12: "when you do win+shift+s i want a macos
// style toolbar"). macOS's Cmd+Shift+5 panel is one row of mode buttons plus a
// commit button, and the picker is already the surface every one of those
// modes lives on, so the toolbar is chrome on this surface rather than a
// second one. Six cells: three shot targets and three record targets, screen /
// window / region each. `action` is what the commit does, `mode` is what it
// does it to, orthogonal, so RECORD REGION needs no mode of its own.
//
// Recording is why `action` exists at all. A recording is not a crop of the
// freeze: wf-recorder records LIVE content, so the record path unmaps this
// surface first and hands RecordingService a rectangle, where the shot path
// keeps the surface up so grim photographs the frozen frames. Same selection
// model, opposite teardown order, see _finish() versus _finishRecord().
Scope {
    id: root

    // "smart" | "region" | "windows" | "fullscreen", which rectangles are
    // hinted and whether a freeform drag is allowed, matching upstream's mode
    // names so a keybind ported from omarchy reads the same.
    property string mode: "smart"
    // "shot" | "record", what Return (and the toolbar's commit cell) does
    // with the current selection.
    property string action: "shot"
    property bool isOpen: false

    // Resolved by the caller (ScreenshotIpc) into a real capture.
    signal picked(var rect)
    // The surface is already unmapped when this fires (see _finishRecord).
    // `outputName` rides along because wf-recorder is always pinned to one
    // output and the picker is the only thing that knows which output the
    // picked rectangle lives on.
    signal pickedRecord(var rect, string outputName)
    signal cancelled(string reason)

    // The toolbar, left to right. `key` is both the digit that selects the
    // cell and its 1-based position, so the legend, the Keys handler and the
    // headless `key` verb all read the same number.
    readonly property var _tools: [
        { key: 1, action: "shot",   mode: "fullscreen", icon: "monitor",    label: "SCREEN" },
        { key: 2, action: "shot",   mode: "windows",    icon: "app-window", label: "WINDOW" },
        { key: 3, action: "shot",   mode: "smart",      icon: "crop",       label: "REGION" },
        { key: 4, action: "record", mode: "fullscreen", icon: "monitor",    label: "SCREEN" },
        { key: 5, action: "record", mode: "windows",    icon: "app-window", label: "WINDOW" },
        { key: 6, action: "record", mode: "smart",      icon: "crop",       label: "REGION" }
    ]

    // Which toolbar cell the current action/mode pair lights. `region` (pure
    // freeform, no hints, reachable only from the IPC verb) is the same intent
    // as `smart`, so it lights the same cell rather than leaving the toolbar
    // showing nothing selected at all.
    readonly property int _toolIndex: {
        const mode = root.mode === "region" ? "smart" : root.mode;
        for (var i = 0; i < root._tools.length; i++) {
            if (root._tools[i].action === root.action && root._tools[i].mode === mode)
                return i;
        }
        return -1;
    }

    readonly property bool _recording: root.action === "record"

    readonly property var _shotTools: root._tools.filter(function (t) { return t.action === "shot"; })
    readonly property var _recordTools: root._tools.filter(function (t) { return t.action === "record"; })

    readonly property string _runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

    property var _frames: ({})        // output name -> frozen PNG path
    property int _pendingFreezes: 0
    // grim's own words from the last failed freeze. A surface that declines
    // to map has to be able to say why without a log the caller cannot read.
    property string _lastFreezeError: ""
    property bool _capturing: false   // chrome hidden, ready to be grimmed
    property var _dragRect: null
    property var _hoverRect: null
    property int _cursor: -1          // index into _selectable, -1 = pointer-driven

    // ---- candidate rectangles -------------------------------------------

    // Indexed loop, not .map(): Quickshell.screens is a QML list, which
    // carries length and [] but none of Array.prototype, so an Array method
    // here throws and takes the whole binding with it. Every other consumer
    // in the shell already walks it this way (PolkitDialog.qml:43,
    // Center.qml:50).
    readonly property var _outputRects: {
        const screens = Quickshell.screens;
        const out = [];
        for (var i = 0; i < screens.length; i++) {
            const s = screens[i];
            out.push({ kind: "output", label: s.name, sublabel: "", windowId: "",
                       rect: { x: s.x, y: s.y, width: s.width, height: s.height } });
        }
        return out;
    }

    // Duplicate boxes (tabbed groups, windows stacked at identical geometry)
    // collapse to one: they are indistinguishable on screen, and a duplicate
    // stalls the Tab cycle on the first copy, the same `unique` upstream
    // applies to its own rectangle list.
    readonly property var _windowEntries: {
        const seen = {};
        const withRect = [];
        const withoutRect = [];
        (CompositorService.windows ?? []).forEach(function (w) {
            const entry = { kind: "window", label: w.title || w.appId || "(untitled)",
                            sublabel: w.appId || "", windowId: w.id, rect: w.rect ?? null };
            if (!w.rect) {
                withoutRect.push(entry);
                return;
            }
            const key = w.rect.x + "," + w.rect.y + " " + w.rect.width + "x" + w.rect.height;
            if (seen[key])
                return;
            seen[key] = true;
            withRect.push(entry);
        });
        // Reading order: top to bottom, then left to right.
        withRect.sort(function (a, b) { return a.rect.y - b.rect.y || a.rect.x - b.rect.x; });
        withoutRect.sort(function (a, b) { return a.label.localeCompare(b.label); });
        return { withRect: withRect, withoutRect: withoutRect };
    }

    // Windows the picker can only name, never draw or take. Normally empty,
    // and the list card below simply stops rendering.
    readonly property var _unboxedWindows: root._windowEntries.withoutRect

    readonly property var _hintRects: {
        if (root.mode === "region")
            return [];
        if (root.mode === "windows")
            return root._windowEntries.withRect;
        if (root.mode === "fullscreen")
            return root._outputRects;
        return root._outputRects.concat(root._windowEntries.withRect);
    }

    // What Tab and the arrows walk: drawable windows first in reading order,
    // then whole outputs last (capturing a display is the coarser intent, so
    // it should not sit between two windows). The named-only windows are not
    // in here: grim crops with `-g` and wf-recorder with nothing else, so a
    // window the compositor reports no box for can be neither shot nor
    // recorded. The toolbar narrows this to the mode's own candidates, so
    // SCREEN never cycles through windows and REGION cycles nothing at all.
    readonly property var _selectable: {
        if (root.mode === "region")
            return [];
        if (root.mode === "fullscreen")
            return root._outputRects;
        if (root.mode === "windows")
            return root._windowEntries.withRect;
        return root._windowEntries.withRect.concat(root._outputRects);
    }

    // The named-window card is window selection's affordance, so it follows
    // the modes that actually select windows.
    readonly property bool _namedShown: root._unboxedWindows.length > 0
        && (root.mode === "windows" || root.mode === "smart")

    readonly property var _current: {
        if (root._dragRect)
            return { kind: "drag", label: "", sublabel: "", windowId: "", rect: root._dragRect };
        if (root._cursor >= 0 && root._cursor < root._selectable.length)
            return root._selectable[root._cursor];
        if (root._hoverRect)
            return root._hoverRect;
        return null;
    }

    // ---- lifecycle -------------------------------------------------------

    function open(newMode) {
        if (root.isOpen)
            return "error: picker already open";
        root.mode = newMode || "smart";
        root.action = "shot";
        root._dragRect = null;
        root._hoverRect = null;
        root._cursor = -1;
        root._capturing = false;
        root._frames = ({});
        // The window boxes this surface is about to draw and crop to are only
        // as fresh as the backend's model, which goes stale between refreshes
        // and omits the box entirely for anything opened since startup. That
        // reads here as "window with no rect", which is uncapturable. Ask for
        // a current set before the candidate list is built.
        CompositorService.refreshWindows();

        // No interaction at all: the focused output is the answer, and no
        // surface ever maps. This is the keybind form of "whole display",
        // the toolbar's own SCREEN cell is the interactive one, and reaches
        // the same rectangle through setTool() with the surface already up.
        if (root.mode === "fullscreen") {
            const out = root._focusedOutputRect();
            if (!out)
                return "error: no focused output";
            root.picked(out.rect);
            return "ok";
        }

        root._freeze();
        return "ok";
    }

    function close(reason) {
        if (!root.isOpen && root._pendingFreezes === 0)
            return "error: picker not open";
        // Both settles are stopped before anything else: a cancel that landed
        // inside one of their windows would otherwise fire a commit signal
        // into a caller that has already torn its own capture state down.
        settleTimer.stop();
        recordSettle.stop();
        root.isOpen = false;
        root._capturing = false;
        root._pendingFreezes = 0;
        root.cancelled(reason || "cancelled");
        return "ok";
    }

    // Selects a toolbar cell, what a click on one does, and what the digit
    // keys and the headless `key` verb both route through.
    function setTool(index) {
        if (!root.isOpen)
            return "error: picker not open";
        if (index < 0 || index >= root._tools.length)
            return "error: unknown tool " + index;
        const tool = root._tools[index];
        root.action = tool.action;
        root.mode = tool.mode;
        root._dragRect = null;
        root._hoverRect = null;

        // A switch that left nothing highlighted would leave the commit cell
        // with nothing to act on until the pointer moved. The two modes whose
        // candidate set is knowable up front preselect: the focused output for
        // SCREEN, the first window in reading order for WINDOW. REGION stays
        // pointer-driven, since the drag is its whole affordance.
        root._cursor = -1;
        if (tool.mode === "fullscreen") {
            const focused = root._focusedOutputRect();
            const at = focused ? root._selectable.findIndex(function (e) {
                return e.label === focused.label;
            }) : -1;
            root._cursor = at >= 0 ? at : 0;
        } else if (tool.mode === "windows" && root._selectable.length > 0) {
            root._cursor = 0;
        }
        return "ok";
    }

    function status() {
        return {
            open: root.isOpen,
            mode: root.mode,
            action: root.action,
            tool: root._toolIndex,
            // The honest capability report: how many windows the picker can
            // draw versus only name.
            drawableWindows: root._windowEntries.withRect.length,
            namedWindows: root._unboxedWindows.length,
            cursor: root._cursor,
            selection: root._current ? root._current.rect : null,
            selectionLabel: root._current ? root._current.label : "",
            capturing: root._capturing,
            // The freeze is the only thing between open() and a mapped
            // surface, and it is asynchronous, so its progress has to be
            // observable or a picker that never opens is indistinguishable
            // from one that never tried.
            pendingFreezes: root._pendingFreezes,
            frames: Object.keys(root._frames).length,
            screens: Quickshell.screens.length,
            runtimeDir: root._runtimeDir,
            lastFreezeError: root._lastFreezeError
        };
    }

    function _focusedOutputRect() {
        const name = CompositorService.focusedOutputName;
        const match = root._outputRects.find(function (o) { return o.label === name; });
        return match || root._outputRects[0] || null;
    }

    // ---- freeze ----------------------------------------------------------

    // One grim per output, all before the surface maps. `-o <name>` keeps each
    // frame in its own output's coordinate space, so the surface for that
    // screen can render it 1:1 at the origin.
    function _freeze() {
        const screens = Quickshell.screens;
        root._pendingFreezes = screens.length;
        if (root._pendingFreezes === 0) {
            root.cancelled("no outputs to capture");
            return;
        }
        // Indexed, for the same reason _outputRects is: no Array.prototype
        // on a QML list.
        for (var i = 0; i < screens.length; i++) {
            const s = screens[i];
            const path = root._runtimeDir + "/formalshell-capture-" + s.name + ".png";
            const proc = freezeComponent.createObject(root, { outputName: s.name, framePath: path });
            if (!proc) {
                root._freezeDone(s.name, path, false, "could not create the freeze process");
                continue;
            }
            proc.running = true;
        }
    }

    function _freezeDone(outputName, framePath, ok, why) {
        if (!ok)
            root._lastFreezeError = outputName + ": " + (why || "grim produced nothing");
        // A NEW object, not a mutation of the existing one: QML only re-
        // evaluates bindings on a `var` property when the reference changes,
        // so mutating in place would leave every surface's Image source stale.
        if (ok) {
            const frames = {};
            Object.keys(root._frames).forEach(function (k) { frames[k] = root._frames[k]; });
            frames[outputName] = framePath;
            root._frames = frames;
        }
        root._pendingFreezes -= 1;
        if (root._pendingFreezes > 0)
            return;

        // Fail open, the same contract the lock surface holds: a picker that
        // cannot show the frozen screen must not map at all, or it would be a
        // full-screen scrim over live content with nothing to select from.
        if (Object.keys(root._frames).length === 0) {
            console.warn("RegionPicker: no output could be frozen:", why);
            root.cancelled("freeze failed: " + (why || "grim produced nothing"));
            return;
        }
        root.isOpen = true;
    }

    Component {
        id: freezeComponent

        // Plain properties rather than `required`: these are set through
        // createObject's initial-property map, and a required property that
        // the map somehow missed would fail instantiation outright rather
        // than degrade, on a freeze path whose whole job is to fail open.
        Process {
            id: freezeProc
            property string outputName: ""
            property string framePath: ""

            // mkdir first: $XDG_RUNTIME_DIR/formalshell is not created by
            // anything the picker can rely on having run, and a missing
            // parent makes grim fail for every output, which the fail-open
            // contract below correctly turns into a surface that never maps.
            // mkdir first: the frame path's parent is whatever
            // XDG_RUNTIME_DIR resolves to, which is not guaranteed to exist
            // on a session that never created it.
            command: ["sh", "-c", 'mkdir -p "$(dirname "$2")" && exec grim -o "$1" "$2"', "sh", outputName, framePath]
            // Started by _freeze() after createObject, never by a declarative
            // `running: true`: that latches while `command` is still binding
            // against the properties the initial-property map is in the
            // middle of applying, and a Process that fails to start never
            // emits `exited` at all (see CommandModule.qml's own note on
            // quickshell's process.cpp). The freeze counter would then never
            // decrement and the picker would hang unopened forever, with no
            // warning, which is exactly how this presented.
            running: false
            property bool sawExit: false
            stderr: StdioCollector { id: freezeErr }
            onExited: exitCode => {
                freezeProc.sawExit = true;
                root._freezeDone(freezeProc.outputName, freezeProc.framePath,
                                 exitCode === 0, freezeErr.text.trim());
                // Never destroy an object from inside its own signal handler:
                // the handler is still on the stack.
                Qt.callLater(function () { freezeProc.destroy(); });
            }
            // A command that never started reports only through this, so it
            // has to settle the freeze the same way an exit does. Without it
            // one unstartable grim strands the whole picker.
            onRunningChanged: {
                if (!freezeProc.running && !freezeProc.sawExit) {
                    root._freezeDone(freezeProc.outputName, freezeProc.framePath,
                                     false, "grim failed to start");
                    Qt.callLater(function () { freezeProc.destroy(); });
                }
            }
        }
    }

    // ---- selection -------------------------------------------------------

    // slurp highlights the smallest box containing the point and keeps the
    // first on a tie; resolving the same way here keeps a floating window over
    // a tiled one selectable, which was upstream's own bug report.
    function _resolveAt(x, y) {
        var best = null;
        var bestArea = 0;
        root._hintRects.forEach(function (candidate) {
            const r = candidate.rect;
            if (x < r.x || x >= r.x + r.width || y < r.y || y >= r.y + r.height)
                return;
            const area = r.width * r.height;
            if (!best || area < bestArea) {
                best = candidate;
                bestArea = area;
            }
        });
        return best;
    }

    function _moveCursor(delta) {
        const n = root._selectable.length;
        if (n === 0)
            return;
        if (root._cursor < 0) {
            // Entering keyboard selection from a pointer hover starts at
            // whatever is highlighted, so Tab continues rather than jumps.
            const hovered = root._hoverRect;
            const at = hovered ? root._selectable.findIndex(function (e) {
                return e.windowId === hovered.windowId && e.label === hovered.label;
            }) : -1;
            root._cursor = at >= 0 ? at : (delta > 0 ? 0 : n - 1);
            return;
        }
        root._cursor = (root._cursor + delta + n) % n;
    }

    // Spatial move, scoring `primary + perp * 2` over candidate centres the
    // way upstream does. Only entries with a rect can take part: a window the
    // compositor gave no box for has no position to move toward, so the
    // arrows fall back to sequential movement through the named list.
    function _moveSpatial(direction) {
        const from = root._current;
        if (!from || !from.rect) {
            root._moveCursor(direction === "up" || direction === "left" ? -1 : 1);
            return;
        }
        const ox = from.rect.x + from.rect.width / 2;
        const oy = from.rect.y + from.rect.height / 2;

        var best = -1;
        var bestScore = 0;
        root._selectable.forEach(function (entry, i) {
            if (!entry.rect || entry === from)
                return;
            const cx = entry.rect.x + entry.rect.width / 2;
            const cy = entry.rect.y + entry.rect.height / 2;
            var primary, perp;
            switch (direction) {
            case "left":  primary = ox - cx; perp = cy - oy; break;
            case "right": primary = cx - ox; perp = cy - oy; break;
            case "up":    primary = oy - cy; perp = cx - ox; break;
            default:      primary = cy - oy; perp = cx - ox; break;
            }
            if (primary <= 0)
                return;
            const score = primary + Math.abs(perp) * 2;
            if (best < 0 || score < bestScore) {
                best = i;
                bestScore = score;
            }
        });
        if (best >= 0)
            root._cursor = best;
    }

    // ---- commit ----------------------------------------------------------

    // Return takes whatever is highlighted; Ctrl+Return takes the whole output
    // under it. Upstream settled on this order because the picker highlights a
    // window far more often than a display.
    function commit(wholeOutput) {
        if (!root.isOpen)
            return "error: picker not open";
        const sel = root._current;
        if (!sel)
            return "error: nothing selected";

        if (wholeOutput) {
            const anchor = sel.rect
                ? root._outputRects.find(function (o) {
                    return sel.rect.x >= o.rect.x && sel.rect.x < o.rect.x + o.rect.width
                        && sel.rect.y >= o.rect.y && sel.rect.y < o.rect.y + o.rect.height;
                })
                : root._focusedOutputRect();
            const out = anchor || root._focusedOutputRect();
            if (!out)
                return "error: no output under the selection";
            if (root._recording) {
                root._finishRecord(out.rect);
                return "ok";
            }
            root._finish(out.rect, "");
            return "ok";
        }

        // No box, no `-g`, nothing to crop or record. Refused by name so the
        // answer says which window and why, rather than reporting a capture
        // that failed to start. Nothing selectable reaches here today, the
        // named-only windows are outside `_selectable`.
        if (!sel.rect)
            return "error: no geometry for \"" + sel.label + "\"";

        if (root._recording) {
            root._finishRecord(sel.rect);
            return "ok";
        }

        root._finish(sel.rect, sel.windowId);
        return "ok";
    }

    // Which output a rectangle sits on, by its centre. wf-recorder is always
    // pinned to one output (see RecordingService._launch), and the picker is
    // the only thing that knows where the picked rectangle landed.
    function _outputNameForRect(rect) {
        const cx = rect.x + rect.width / 2;
        const cy = rect.y + rect.height / 2;
        const hit = root._outputRects.find(function (o) {
            return cx >= o.rect.x && cx < o.rect.x + o.rect.width
                && cy >= o.rect.y && cy < o.rect.y + o.rect.height;
        });
        return hit ? hit.label : "";
    }

    // The mirror image of _finish(): a recording is of LIVE content, so this
    // surface has to be GONE before wf-recorder starts or the first frames are
    // of the scrim and the frozen frame under it. Unmap first, settle for a
    // frame, then hand the rectangle over.
    function _finishRecord(rect) {
        root.isOpen = false;
        root._capturing = false;
        recordSettle.pendingRect = rect;
        recordSettle.restart();
    }

    Timer {
        id: recordSettle
        // Same order of magnitude as settleTimer's: one frame for the
        // compositor to drop the layer surface it was just told to unmap.
        interval: 120
        property var pendingRect: null
        onTriggered: {
            const rect = recordSettle.pendingRect;
            recordSettle.pendingRect = null;
            root.pickedRecord(rect, root._outputNameForRect(rect));
        }
    }

    // The overlay is showing the frozen frames, so grim pointed at this
    // surface captures the frozen content, upstream grims hyprpicker's freeze
    // layer for exactly the same reason. Chrome drops for a frame first so the
    // scrim and readout are not baked in.
    function _finish(rect, windowId) {
        root._capturing = true;
        settleTimer.pendingRect = rect;
        settleTimer.restart();
    }

    // The surface stays MAPPED across this, showing the frozen frames with its
    // chrome hidden, that is the whole point, since grim photographs the
    // screen and the screen is this overlay. The caller closes it with done()
    // once grim has exited, exactly as upstream keeps hyprpicker's freeze
    // alive until after its own grim returns.
    Timer {
        id: settleTimer
        // One frame is the requirement; this is the same order of magnitude as
        // upstream's `sleep .1` after starting its freeze.
        interval: 80
        property var pendingRect: null
        onTriggered: {
            const rect = settleTimer.pendingRect;
            settleTimer.pendingRect = null;
            root.picked(rect);
        }
    }

    // Tears the surface down after the caller's capture has finished. Separate
    // from close() because this is a completed pick, not a cancellation, and
    // must not fire the cancelled signal.
    function done() {
        settleTimer.stop();
        recordSettle.stop();
        root.isOpen = false;
        root._capturing = false;
        return "ok";
    }

    // ---- headless drive (smoke rig) --------------------------------------

    // The same division every other surface already uses: real keyboard input
    // is the feature, this is how the rig exercises it without depending on
    // synthetic key delivery into an Exclusive-focus layer surface.
    function key(name) {
        if (!root.isOpen)
            return "error: picker not open";
        switch (name) {
        case "return":       return root.commit(false);
        case "ctrl-return":  return root.commit(true);
        case "tab":          root._moveCursor(1); return "ok";
        case "shift-tab":    root._moveCursor(-1); return "ok";
        case "left":
        case "right":
        case "up":
        case "down":         root._moveSpatial(name); return "ok";
        case "escape":       return root.close("cancelled from the picker");
        case "1": case "2": case "3":
        case "4": case "5": case "6":
            return root.setTool(Number(name) - 1);
        default:             return "error: unknown key " + name;
        }
    }

    // ---- surface ---------------------------------------------------------

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: surface
            required property var modelData

            screen: modelData
            visible: root.isOpen
            color: "transparent"

            WlrLayershell.namespace: "formalshell:capture"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            anchors { top: true; bottom: true; left: true; right: true }

            readonly property string _frameSource: {
                const p = root._frames[surface.modelData.name];
                return p ? "file://" + p : "";
            }

            // Surface-local coordinates from a logical rect, and back. Every
            // rect in this file is in the compositor's logical space; only
            // these two conversions know about this screen's origin.
            function toLocalX(x) { return x - surface.modelData.x; }
            function toLocalY(y) { return y - surface.modelData.y; }
            function toGlobalX(x) { return x + surface.modelData.x; }
            function toGlobalY(y) { return y + surface.modelData.y; }

            // The frozen screen. This is what grim photographs at capture time,
            // so it sits under everything.
            //
            // Stretched onto the surface rather than padded at natural size:
            // grim writes the output's BUFFER, in physical pixels, while this
            // layer surface is sized in logical ones. On any output whose scale
            // is not 1 the two differ, and padding renders the capture 1:1 from
            // the top-left corner, which shows a fraction of the screen blown
            // up. Stretching maps the photograph back onto the exact logical
            // box it was taken from, at any scale, which is also the space
            // every rect in this file already lives in. `smooth` matters only
            // where that mapping actually resamples; on a scale-1 output the
            // source and the surface agree and it costs nothing.
            Image {
                id: frozen
                anchors.fill: parent
                source: surface._frameSource
                fillMode: Image.Stretch
                smooth: true
                cache: false
            }

            // Scrim over everything except the current selection. Four
            // rectangles rather than one with a hole: no blur, no shaders, no
            // masks (DESIGN.md, and CLAUDE.md's brutalist defaults).
            Item {
                anchors.fill: parent
                visible: !root._capturing

                readonly property var sel: root._current ? root._current.rect : null
                readonly property real sx: sel ? surface.toLocalX(sel.x) : 0
                readonly property real sy: sel ? surface.toLocalY(sel.y) : 0
                readonly property real sw: sel ? sel.width : 0
                readonly property real sh: sel ? sel.height : 0

                Rectangle {
                    color: Core.Theme.color.background
                    opacity: 0.6
                    x: 0; y: 0
                    width: parent.width
                    height: parent.sel ? Math.max(0, parent.sy) : parent.height
                }
                Rectangle {
                    color: Core.Theme.color.background
                    opacity: 0.6
                    visible: parent.sel !== null
                    x: 0
                    y: parent.sy + parent.sh
                    width: parent.width
                    height: Math.max(0, parent.height - (parent.sy + parent.sh))
                }
                Rectangle {
                    color: Core.Theme.color.background
                    opacity: 0.6
                    visible: parent.sel !== null
                    x: 0
                    y: parent.sy
                    width: Math.max(0, parent.sx)
                    height: parent.sh
                }
                Rectangle {
                    color: Core.Theme.color.background
                    opacity: 0.6
                    visible: parent.sel !== null
                    x: parent.sx + parent.sw
                    y: parent.sy
                    width: Math.max(0, parent.width - (parent.sx + parent.sw))
                    height: parent.sh
                }
            }

            // Selection border and its dimension readout.
            Item {
                id: selectionChrome
                anchors.fill: parent
                visible: !root._capturing && root._current !== null

                readonly property var sel: root._current ? root._current.rect : null

                // primitive-exempt: a selection marquee is a 2px rule around a
                // rectangle the pointer is dragging, not a surface. No
                // primitive draws one, and `Cell` would bring a fill and a
                // radius that would cover and round the very region being
                // measured.
                Rectangle {
                    visible: selectionChrome.sel !== null
                    x: selectionChrome.sel ? surface.toLocalX(selectionChrome.sel.x) : 0
                    y: selectionChrome.sel ? surface.toLocalY(selectionChrome.sel.y) : 0
                    width: selectionChrome.sel ? selectionChrome.sel.width : 0
                    height: selectionChrome.sel ? selectionChrome.sel.height : 0
                    color: "transparent"
                    // The record action borrows the recording indicator's own
                    // `urgent` role, the same swap the slurp-driven record
                    // selection already made (RecordingService's FS_SLURP_
                    // BORDER), one look for "this is about to record".
                    border.color: root._recording ? Core.Theme.color.destructive : Core.Theme.color.primary
                    border.width: Core.Theme.borderWidth * 2
                }

                // Readout rides just outside the top-left corner, flipping
                // inside when the selection is against the screen edge.
                Cell {
                    id: readout
                    radius: Core.Theme.radiusSm
                    visible: selectionChrome.sel !== null
                    x: selectionChrome.sel ? Math.max(0, surface.toLocalX(selectionChrome.sel.x)) : 0
                    y: {
                        if (!selectionChrome.sel)
                            return 0;
                        const above = surface.toLocalY(selectionChrome.sel.y) - height - Core.Theme.space.xs;
                        return above >= 0 ? above : surface.toLocalY(selectionChrome.sel.y) + Core.Theme.space.xs;
                    }

                    Row {
                        spacing: Core.Theme.space.sm

                        Text {
                            text: selectionChrome.sel
                                ? Math.round(selectionChrome.sel.width) + "×" + Math.round(selectionChrome.sel.height)
                                : ""
                            color: readout.foreground
                            font.family: Core.Theme.fontFamilyMono
                            font.pixelSize: Core.Theme.fontSize.caption
                        }
                        SectionLabel {
                            visible: text.length > 0
                            text: root._current && root._current.kind !== "drag" ? root._current.label : ""
                            color: readout.dimForeground
                        }
                    }
                }
            }

            // Windows the compositor gave no box for. Renders only when such
            // windows exist, so it is normally absent.
            Card {
                id: nameList
                visible: !root._capturing && root._namedShown
                // Opaque, unlike the panels and the bar: `formalshell:capture`
                // is not one of the three namespaces Hyprland blurs behind, and
                // a translucent card over the frozen screenshot would be
                // unreadable (spec "Depth").
                color: Core.Theme.color.card
                width: Core.Theme.space.popupWidthWide
                height: listColumn.height + nameList.padding * 2
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)

                Column {
                    id: listColumn
                    width: parent.width

                    SectionLabel {
                        // The header carries the whole explanation rather than
                        // leaving the dimmed rows to imply it.
                        text: "CANNOT CAPTURE: NO COMPOSITOR GEOMETRY"
                        color: Core.Theme.color.mutedForeground
                        // Lines up with the row text below rather than with the
                        // card edge: the rows are ghosts, so they draw no border
                        // for it to sit against (DESIGN.md §1 Padding).
                        leftPadding: Core.Theme.space.controlPaddingX
                    }

                    Repeater {
                        model: root._unboxedWindows

                        delegate: Cell {
                            id: windowRow
                            required property int index
                            required property var modelData
                            width: listColumn.width
                            ghost: true
                            // Named-only windows are outside _selectable, so
                            // the cursor never lands on one of these rows.
                            selected: false

                            Column {
                                width: parent.width

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: windowRow.modelData.label
                                    color: Core.Theme.color.mutedForeground
                                    font.family: Core.Theme.fontFamilySans
                                    font.pixelSize: Core.Theme.fontSize.body
                                }
                                SectionLabel {
                                    visible: windowRow.modelData.sublabel.length > 0
                                    text: windowRow.modelData.sublabel
                                    color: Core.Theme.color.mutedForeground
                                }
                            }
                        }
                    }
                }
            }

            // Key legend, sitting just above the toolbar. The record action
            // changes what Return means, so the hint follows the current tool
            // rather than stating one fixed contract.
            Cell {
                id: legend
                visible: !root._capturing
                x: Math.round((parent.width - width) / 2)
                y: toolbar.y - height - Core.Theme.space.md

                SectionLabel {
                    text: "RETURN " + (root._recording ? "RECORD" : "CAPTURE")
                        + "  ·  CTRL+RETURN DISPLAY  ·  TAB CYCLE  ·  1-6 TOOL  ·  ESC CANCEL"
                    color: legend.dimForeground
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.CrossCursor

                property real pressX: 0
                property real pressY: 0

                onPositionChanged: mouse => {
                    if (root._dragRect) {
                        root._dragRect = {
                            x: surface.toGlobalX(Math.min(pressX, mouse.x)),
                            y: surface.toGlobalY(Math.min(pressY, mouse.y)),
                            width: Math.abs(mouse.x - pressX),
                            height: Math.abs(mouse.y - pressY)
                        };
                        return;
                    }
                    // Pointer movement takes the selection back from the
                    // keyboard, the same way a hover overrides a cursor
                    // anywhere else in the shell.
                    root._cursor = -1;
                    root._hoverRect = root._resolveAt(surface.toGlobalX(mouse.x), surface.toGlobalY(mouse.y));
                }

                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        root.close("cancelled by right-click");
                        return;
                    }
                    pressX = mouse.x;
                    pressY = mouse.y;
                    // Freeform is REGION's affordance and smart's fallback.
                    // WINDOW and SCREEN snap to what they hint, so a drag
                    // there would silently produce a rectangle the mode never
                    // offered.
                    if (root.mode === "smart" || root.mode === "region")
                        root._dragRect = { x: surface.toGlobalX(mouse.x), y: surface.toGlobalY(mouse.y), width: 0, height: 0 };
                }

                onReleased: mouse => {
                    const drag = root._dragRect;
                    root._dragRect = null;
                    // A bare click, under upstream's own 20px² threshold,
                    // snaps to whatever rectangle it landed in rather than
                    // capturing an accidental two-pixel sliver.
                    if (!drag || drag.width * drag.height < 20) {
                        root._hoverRect = root._resolveAt(surface.toGlobalX(mouse.x), surface.toGlobalY(mouse.y));
                        if (root._hoverRect)
                            root.commit(false);
                        return;
                    }
                    if (root._recording) {
                        root._finishRecord(drag);
                        return;
                    }
                    root._finish(drag, "");
                }
            }

            // The toolbar (owner ask, see the file header): the surface's whole
            // mode set as one row of cells over a bordered card, in the bar's
            // standalone-cell idiom (borderless at rest, full inversion on
            // hover, current tool inverted) rather than the fused ledger, six
            // discrete buttons is what the bar's own chrome is for. Declared
            // after the drag MouseArea so it sits on top of it and takes its
            // own clicks.
            Card {
                id: toolbar
                visible: !root._capturing
                // Opaque, for the same reason nameList above is.
                color: Core.Theme.color.card
                width: toolbarRow.width + toolbar.padding * 2
                height: toolbarRow.height + toolbar.padding * 2
                x: Math.round((parent.width - width) / 2)
                y: parent.height - height - Core.Theme.space.xl

                // Absorbs everything landing on the card: a click on its chrome
                // must never reach the drag area underneath, and a pointer
                // crossing it must never re-resolve the selection out from
                // under the cell being aimed at. The negative margins take it
                // back out past the card's own padding, which the default slot
                // is already inset by.
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -toolbar.padding
                    hoverEnabled: true
                    acceptedButtons: Qt.AllButtons
                }

                Component {
                    id: toolCellComponent

                    Cell {
                        id: toolCell
                        required property var modelData
                        ghost: true
                        selected: root._toolIndex === toolCell.modelData.key - 1

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Core.Theme.space.sm

                            Icon {
                                name: toolCell.modelData.icon
                                color: toolCell.foreground
                            }
                            SectionLabel {
                                anchors.verticalCenter: parent.verticalCenter
                                text: toolCell.modelData.label
                                color: toolCell.dimForeground
                            }
                        }

                        interactive: true
                        onClicked: root.setTool(toolCell.modelData.key - 1)
                    }
                }

                Row {
                    id: toolbarRow
                    spacing: Core.Theme.space.md

                    SectionLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "SHOT"
                        color: Core.Theme.color.mutedForeground
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter

                        Repeater {
                            model: root._shotTools
                            delegate: toolCellComponent
                        }
                    }

                    SectionLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "REC"
                        color: Core.Theme.color.mutedForeground
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter

                        Repeater {
                            model: root._recordTools
                            delegate: toolCellComponent
                        }
                    }

                    // The ink button (DESIGN.md §2 item 11): the one committing
                    // action on the surface, and the same thing Return fires.
                    Cell {
                        id: commitCell
                        anchors.verticalCenter: parent.verticalCenter
                        ghost: true
                        active: true

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Core.Theme.space.sm

                            Icon {
                                name: root._recording ? "video" : "camera"
                                color: commitCell.foreground
                            }
                            SectionLabel {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root._recording ? "RECORD" : "CAPTURE"
                                color: commitCell.dimForeground
                            }
                        }

                        interactive: true
                        onClicked: root.commit(false)
                    }
                }
            }

            Item {
                anchors.fill: parent
                focus: root.isOpen

                Keys.onPressed: event => {
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                    switch (event.key) {
                    case Qt.Key_Escape:
                        root.close("cancelled from the picker");
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.commit(ctrl);
                        break;
                    case Qt.Key_Tab:
                        root._moveCursor(1);
                        break;
                    case Qt.Key_Backtab:
                        root._moveCursor(-1);
                        break;
                    case Qt.Key_Left:
                        root._moveSpatial("left");
                        break;
                    case Qt.Key_Right:
                        root._moveSpatial("right");
                        break;
                    case Qt.Key_Up:
                        root._moveSpatial("up");
                        break;
                    case Qt.Key_Down:
                        root._moveSpatial("down");
                        break;
                    case Qt.Key_1:
                    case Qt.Key_2:
                    case Qt.Key_3:
                    case Qt.Key_4:
                    case Qt.Key_5:
                    case Qt.Key_6:
                        // Contiguous by definition (Qt.Key_1 is 0x31), so the
                        // digit is the offset, no per-key branch.
                        root.setTool(event.key - Qt.Key_1);
                        break;
                    default:
                        // Shift is free here: upstream had to avoid it because
                        // slurp squares its selection while Shift is held.
                        if (shift && event.key === Qt.Key_Tab)
                            root._moveCursor(-1);
                        return;
                    }
                    event.accepted = true;
                }
            }
        }
    }
}

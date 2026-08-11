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
// namespace. niri has neither a cursor-warp action nor dynamic layer-scoped
// binds, and the shell cannot inject binds into a compositor at runtime. So
// the picker is the shell's own Overlay surface, which owns its highlight
// state directly: no warping, no compositor binds, one code path on both
// backends. Every probe-for-a-reachable-warp-point mechanism upstream had to
// invent exists only to steer a picker that does not know what is selected,
// and has no counterpart here.
//
// ⚠️ THE ONE ASYMMETRY BETWEEN BACKENDS. niri reports a pixel box only for
// FLOATING windows: `Tile::ipc_layout_template` hardcodes
// `tile_pos_in_workspace_view: None` (niri v26.04 src/layout/tile.rs:869),
// floating.rs:336 fills it in, and the scrolling (tiled) layout overrides
// only `pos_in_scrolling_layout` (src/layout/scrolling.rs:2426) and inherits
// that None. `pos_in_scrolling_layout` is a 1-based (column, row) index pair,
// not pixels. So a tiled niri window has NO rectangle to draw, and on
// Hyprland every window has one.
//
// Window SELECTION exists on both regardless; only the affordance differs.
// A window with a rect is highlighted on screen; a window without one is
// named in a labelled list (title over dim app id) and captured by id through
// niri's `ScreenshotWindow` action, which crops server-side. The split is on
// `rect === null`, never on a backend name, so a future niri that starts
// reporting tiled geometry turns this into the Hyprland behaviour with no
// redesign here.
//
// The freeze is upstream's trick, kept: grim captures each output BEFORE the
// surface maps, the surface renders those frames 1:1, and the capture then
// grims the surface itself with the chrome hidden for a frame. Content cannot
// shift mid-pick, and the overlay cannot photograph its own scrim. No
// ScreencopyView is involved anywhere (LockSurface.qml's header: it crashes
// the shell outright).
Scope {
    id: root

    // "smart" | "region" | "windows" | "fullscreen" — which rectangles are
    // hinted and whether a freeform drag is allowed, matching upstream's mode
    // names so a keybind ported from omarchy reads the same.
    property string mode: "smart"
    property bool isOpen: false

    // Resolved by the caller (ScreenshotIpc) into a real capture.
    signal picked(var rect)
    signal pickedWindow(string windowId)
    signal cancelled(string reason)

    readonly property string _runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

    property var _frames: ({})        // output name -> frozen PNG path
    property int _pendingFreezes: 0
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
    // stalls the Tab cycle on the first copy — the same `unique` upstream
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

    // Windows the picker can only name, never draw. Empty on Hyprland, and
    // empty on any future niri that reports tiled geometry — the list card
    // below simply stops rendering, with no branch on compositor name.
    readonly property var _unboxedWindows: root._windowEntries.withoutRect

    readonly property var _hintRects: {
        if (root.mode === "region")
            return [];
        if (root.mode === "windows")
            return root._outputRects.concat(root._windowEntries.withRect);
        return root._outputRects.concat(root._windowEntries.withRect);
    }

    // What Tab and the arrows walk: drawable windows first in reading order,
    // then the named-only ones, then whole outputs last (capturing a display
    // is the coarser intent, so it should not sit between two windows).
    readonly property var _selectable: root._windowEntries.withRect
        .concat(root._unboxedWindows)
        .concat(root._outputRects)

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
        root._dragRect = null;
        root._hoverRect = null;
        root._cursor = -1;
        root._capturing = false;
        root._frames = ({});

        // No interaction at all: the focused output is the answer, and no
        // surface ever maps.
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
        root.isOpen = false;
        root._capturing = false;
        root._pendingFreezes = 0;
        root.cancelled(reason || "cancelled");
        return "ok";
    }

    function status() {
        return {
            open: root.isOpen,
            mode: root.mode,
            // The honest capability report: how many windows the picker can
            // draw versus only name. Zero drawable with a non-empty named
            // list is the normal niri answer, not a failure.
            drawableWindows: root._windowEntries.withRect.length,
            namedWindows: root._unboxedWindows.length,
            cursor: root._cursor,
            selection: root._current ? root._current.rect : null,
            selectionLabel: root._current ? root._current.label : "",
            capturing: root._capturing
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
        // than degrade — on a freeze path whose whole job is to fail open.
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
            root._finish(out.rect, "");
            return "ok";
        }

        // A window with no rect can only be captured by id, server-side. The
        // overlay is irrelevant to that path: niri crops the window's own
        // buffer, not the screen, so what is on top of it does not matter.
        if (sel.kind === "window" && !sel.rect) {
            root.isOpen = false;
            root.pickedWindow(sel.windowId);
            return "ok";
        }

        root._finish(sel.rect, sel.windowId);
        return "ok";
    }

    // The overlay is showing the frozen frames, so grim pointed at this
    // surface captures the frozen content — upstream grims hyprpicker's freeze
    // layer for exactly the same reason. Chrome drops for a frame first so the
    // scrim and readout are not baked in.
    function _finish(rect, windowId) {
        root._capturing = true;
        settleTimer.pendingRect = rect;
        settleTimer.restart();
    }

    // The surface stays MAPPED across this, showing the frozen frames with its
    // chrome hidden — that is the whole point, since grim photographs the
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

            // The frozen screen, 1:1. This is what grim photographs at capture
            // time, which is why it sits under everything and is never scaled.
            Image {
                id: frozen
                anchors.fill: parent
                source: surface._frameSource
                fillMode: Image.Pad
                smooth: false
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

                Rectangle {
                    visible: selectionChrome.sel !== null
                    x: selectionChrome.sel ? surface.toLocalX(selectionChrome.sel.x) : 0
                    y: selectionChrome.sel ? surface.toLocalY(selectionChrome.sel.y) : 0
                    width: selectionChrome.sel ? selectionChrome.sel.width : 0
                    height: selectionChrome.sel ? selectionChrome.sel.height : 0
                    color: "transparent"
                    border.color: Core.Theme.color.accent
                    border.width: Core.Theme.borderWidth
                    radius: 0
                }

                // Readout rides just outside the top-left corner, flipping
                // inside when the selection is against the screen edge.
                Cell {
                    id: readout
                    standalone: true
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

                        MetaLabel {
                            text: selectionChrome.sel
                                ? Math.round(selectionChrome.sel.width) + "×" + Math.round(selectionChrome.sel.height)
                                : ""
                            color: readout.foreground
                        }
                        MetaLabel {
                            visible: text.length > 0
                            text: root._current && root._current.kind !== "drag" ? root._current.label.toUpperCase() : ""
                            color: readout.dimForeground
                        }
                    }
                }
            }

            // Windows the compositor gave no box for. Renders only when such
            // windows exist, so it is absent on Hyprland and absent on any
            // niri that starts reporting tiled geometry.
            Rectangle {
                id: nameList
                visible: !root._capturing && root._unboxedWindows.length > 0
                color: Core.Theme.color.background
                border.color: Core.Theme.color.rule
                border.width: Core.Theme.borderWidth
                radius: 0
                width: Core.Theme.space.popupWidthWide
                height: listColumn.height + Core.Theme.space.popupPadding * 2
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)

                Column {
                    id: listColumn
                    x: Core.Theme.space.popupPadding
                    y: Core.Theme.space.popupPadding
                    width: parent.width - Core.Theme.space.popupPadding * 2

                    MetaLabel {
                        text: "SELECT WINDOW"
                        color: Core.Theme.color.foregroundDim
                    }

                    Repeater {
                        model: root._unboxedWindows

                        delegate: Cell {
                            id: windowRow
                            required property int index
                            required property var modelData
                            width: listColumn.width
                            // The cursor walks _selectable, whose named-only
                            // entries start after the drawable ones.
                            selected: root._cursor === root._windowEntries.withRect.length + windowRow.index

                            Column {
                                width: parent.width

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: windowRow.modelData.label
                                    color: windowRow.foreground
                                    font.family: Core.Theme.fontFamily
                                    font.pixelSize: Core.Theme.fontSize.body
                                }
                                MetaLabel {
                                    visible: windowRow.modelData.sublabel.length > 0
                                    text: windowRow.modelData.sublabel.toUpperCase()
                                    color: windowRow.dimForeground
                                }
                            }
                        }
                    }
                }
            }

            // Key legend. Named windows change what Return means, so the hint
            // follows the selection rather than stating one fixed contract.
            Cell {
                id: legend
                standalone: true
                visible: !root._capturing
                x: Math.round((parent.width - width) / 2)
                y: parent.height - height - Core.Theme.space.xl

                MetaLabel {
                    text: "RETURN CAPTURE  ·  CTRL+RETURN DISPLAY  ·  TAB CYCLE  ·  ESC CANCEL"
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
                    if (root.mode !== "windows")
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
                    root._finish(drag, "");
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

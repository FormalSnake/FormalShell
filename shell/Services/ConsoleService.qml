pragma Singleton

import QtQuick
import Quickshell
import qs.Core as Core
import qs.Compositor
import qs.Notifications

import "../Console/geometry.js" as Geometry

// The quake console: one terminal that drops down over whatever workspace
// you are on and goes away again with the session inside it still running
// (M37). The window is the terminal's own — the shell is pure QML/JS and has
// no emulator to embed — so this service owns exactly three things: spawning
// it once, placing it, and moving it in and out of view.
//
// Visibility is DERIVED, never stored: the console is showing when the
// compositor reports its window on the focused workspace. That survives a
// shell restart (a restarted shell adopts the console already running rather
// than spawning a second one), a compositor-side move, and the user parking
// it by hand, with no state.json key to drift out of sync.
//
// Hiding is where the two backends differ, and the difference stays behind
// CompositorService.parkWindow: Hyprland has a special workspace, niri has
// no hide primitive of any kind and parks on another workspace instead.
//
// The spawn -> map -> float -> place sequence is the one RecordingService's
// webcam overlay already proves out (its own two timers, same 5s bound):
// a freshly spawned window carries no id this shell knows, so identity has
// to come from what the terminal was told to call itself.
Singleton {
    id: root

    readonly property string appId: Core.Config.get("console.appId", "dev.formalshell.console")
    readonly property var command: Core.Config.get("console.command", ["ghostty", "--class=dev.formalshell.console"])
    readonly property real share: Core.Config.get("console.share", 0.5)

    // Parking AND floating placement, because a console that cannot be
    // hidden again is worse than no console: nothing gets spawned at all on
    // a compositor missing either.
    readonly property bool available: CompositorService.available
        && CompositorService.windowParkingAvailable
        && CompositorService.floatingPlacementAvailable

    readonly property var consoleWindow: {
        const wins = CompositorService.windows || [];
        for (var i = 0; i < wins.length; i++) {
            if (wins[i].appId === root.appId)
                return wins[i];
        }
        return null;
    }
    readonly property string windowId: root.consoleWindow ? root.consoleWindow.id : ""
    readonly property bool showing: !!root.consoleWindow
        && root.consoleWindow.workspaceId === CompositorService.focusedWorkspaceId
    property bool spawning: false

    function toggle() {
        if (root.showing)
            root.hide();
        else
            root.show();
    }

    function show() {
        if (!root.available) {
            console.warn("ConsoleService: no compositor that can park and place a window");
            NotificationService.notify("CONSOLE UNAVAILABLE", "this compositor cannot place a floating window");
            return;
        }
        if (root.windowId !== "") {
            root._reveal(root.windowId);
            return;
        }
        if (root.spawning)
            return;
        const argv = root.command;
        if (!Array.isArray(argv) || argv.length === 0) {
            console.warn("ConsoleService: console.command is not set");
            NotificationService.notify("CONSOLE UNAVAILABLE", "console.command is not set");
            return;
        }
        root.spawning = true;
        root._attempts = 0;
        CompositorService.spawn(argv);
        mapTimer.restart();
    }

    function hide() {
        if (root.windowId === "")
            return;
        settleTimer.stop();
        CompositorService.parkWindow(root.windowId);
    }

    // The output the console drops onto: the focused one, resolved through
    // Quickshell.screens rather than CompositorService.outputs, whose
    // width/height are the output MODE's physical pixels while every
    // placement dispatcher works in logical ones (RecordingService's
    // _webcamRegion resolves the same split the same way; Quickshell.screens
    // is a QML list, hence the indexed loop).
    function _screen() {
        const name = CompositorService.focusedOutputName;
        const screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return { x: screens[i].x, y: screens[i].y, width: screens[i].width, height: screens[i].height };
        }
        return screens.length > 0
            ? { x: screens[0].x, y: screens[0].y, width: screens[0].width, height: screens[0].height }
            : null;
    }

    property string _pendingId: ""
    property string _targetWorkspaceId: ""
    property var _target: null
    property int _attempts: 0
    property bool _placed: false

    // Brings `id` here whether it was parked, sitting on a workspace the user
    // walked away from, or already on this one: the move is a no-op in the
    // last case, and re-placing on every show is what keeps a rescaled output
    // from leaving the console at yesterday's size.
    function _reveal(id) {
        root._target = Geometry.consoleGeometry(root._screen(), Core.Theme.barHeight,
            root.share, Core.Theme.space.xl);
        if (!root._target) {
            console.warn("ConsoleService: no output to place the console on");
            NotificationService.notify("CONSOLE UNPLACED", "no output to place the console on");
            return;
        }
        root._pendingId = id;
        root._targetWorkspaceId = CompositorService.focusedWorkspaceId;
        root._attempts = 0;
        root._placed = false;
        CompositorService.unparkWindow(id);
        CompositorService.floatWindow(id);
        settleTimer.restart();
    }

    // Waits for the spawned terminal to map, matched by app id. A terminal
    // that never announces `console.appId` (the flag differs per emulator and
    // both keys have to agree) is the likely cause, so the give-up message
    // names it rather than blaming the compositor.
    Timer {
        id: mapTimer
        interval: 50
        repeat: true
        onTriggered: {
            root._attempts++;
            if (root.windowId !== "") {
                mapTimer.stop();
                root.spawning = false;
                root._reveal(root.windowId);
                return;
            }
            if (root._attempts >= 100) {
                mapTimer.stop();
                root.spawning = false;
                console.warn("ConsoleService: no window with app id", root.appId, "opened in time");
                NotificationService.notify("CONSOLE UNAVAILABLE",
                    "no window announcing " + root.appId + " opened");
            }
        }
    }

    // Two-phase on one clock, RecordingService's own webcam pattern: wait for
    // the window to land on this workspace with a real `rect` (proof the
    // unpark and the float took) before resizing it, then wait for the size
    // it reports to match what was asked (proof the placement took) before
    // focusing. Focus comes last on purpose — focusing a window still sitting
    // on the park workspace would drag the user's view over to it.
    Timer {
        id: settleTimer
        interval: 50
        repeat: true
        onTriggered: {
            root._attempts++;
            const win = (CompositorService.windows || []).find(w => w.id === root._pendingId);
            if (!win) {
                if (root._attempts >= 40) {
                    settleTimer.stop();
                    console.warn("ConsoleService: the console window went away while being placed");
                }
                return;
            }
            const rect = win.rect;
            const landed = win.workspaceId === root._targetWorkspaceId;
            if (landed && rect && !root._placed) {
                root._placed = true;
                root._attempts = 0;
                CompositorService.placeFloatingWindow(win.id, root._target.x, root._target.y,
                    root._target.width, root._target.height);
                return;
            }
            if (landed && rect && root._placed
                && Math.round(rect.width) === root._target.width
                && Math.round(rect.height) === root._target.height) {
                settleTimer.stop();
                CompositorService.focusWindow(win.id);
                return;
            }
            if (root._attempts >= 40) {
                settleTimer.stop();
                console.warn("ConsoleService: the console did not settle in time, focusing it anyway");
                CompositorService.focusWindow(win.id);
            }
        }
    }
}

pragma Singleton
import QtQuick
import Quickshell
import qs.Compositor
import qs.Core as Core
import "../Display/priority.js" as Priority

// The shell's main output: `display.outputPriority`'s first entry with a
// connected screen, e.g. ["HDMI", "internal"] for "the desk monitor while
// it's plugged in, the laptop panel when it isn't". One answer, resolved in
// one place, so every surface that has to name a single screen (the
// screensaver's animated head, the monitor panel and view, the display
// panel's output rows) agrees on which one it is.
//
// `mainOutput` is bound live: it re-resolves off Quickshell.screens and the
// focused output, so a plug or unplug moves it immediately. Callers that
// must NOT move mid-run pass their current pick to resolve() instead —
// Screensaver.qml's own stickiness, which exists because restarting ttfx on
// a new screen replays the effect from frame 0.
//
// A priority list matching nothing connected is a typo, not a state to
// render: it warns once and falls back to focus rather than answering "".
Singleton {
    id: root

    readonly property var priority: Core.Config.get("display.outputPriority", [])
    readonly property var _screens: Quickshell.screens
    readonly property var _names: Priority.screenNames(root._screens)

    readonly property string mainOutput: Priority.resolveMainOutput(root._names, root.priority,
        CompositorService.focusedOutputName, "")

    function resolve(current) {
        return Priority.resolveMainOutput(root._names, root.priority,
            CompositorService.focusedOutputName, current);
    }

    function isMain(name) {
        return name !== "" && name === root.mainOutput;
    }

    // Warned from a handler, not from the mainOutput binding: the flag is
    // both read and written here, and a binding that did that would list
    // itself as its own dependency.
    property bool _loggedUnmatched: false

    on_NamesChanged: root._warnUnmatched()
    Component.onCompleted: root._warnUnmatched()

    function _warnUnmatched() {
        if (root._loggedUnmatched || root._names.length === 0)
            return;
        if (Priority.priorityList(root.priority).length === 0)
            return;
        if (Priority.matchPriority(root._names, root.priority) !== "")
            return;
        console.warn("MainOutputService: no output matches display.outputPriority ("
            + JSON.stringify(root.priority) + "), falling back to the focused one of "
            + JSON.stringify(root._names));
        root._loggedUnmatched = true;
    }
}

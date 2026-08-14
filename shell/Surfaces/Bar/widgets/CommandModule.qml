import QtQuick
import Quickshell.Io
import qs.Core
import qs.Components
import "../../../Bar/commandOutput.js" as CommandOutput

// Bar cell for a `bar.modules[]` entry with type "command" (DESIGN.md
// §Bar, spec §Surfaces-1, M10 Task 3): runs `module.command` on an
// interval and parses its stdout as Waybar-JSON-compatible
// `{text, tooltip, class}`. `text` renders in the cell and `tooltip` goes
// straight to Cell's hover tooltip verbatim — the module author's own
// wording, never reformatted or uppercased here (MetaLabel's own
// `font.capitalization` does the casing on the way out). `class` maps onto
// the two states Cell already has (DESIGN's accent/urgent are flat blocks,
// not arbitrary CSS classes, so only "warning" and "critical"/"urgent" are
// recognised; anything else renders plain). A non-zero exit, a timeout, or
// output that fails to parse as JSON with a string `text` all render the
// same honest "MODULE ERROR" cell — with no tooltip, since
// commandOutput.js's error state carries an empty one — instead of a stale
// value.
Cell {
    id: root

    property var module: null

    readonly property int _interval: (root.module && root.module.interval > 0) ? root.module.interval : 5000
    readonly property int _timeout: (root.module && root.module.timeout > 0) ? root.module.timeout : 5000

    property string _text: ""
    property string _tooltip: ""
    property string _class: ""
    // Set true the moment `proc.exited` fires for the in-flight run, so
    // `proc.onRunningChanged` below can tell a normal completion (exited
    // always fires first) apart from a process that never started at all.
    property bool _sawExit: false

    standalone: true
    accent: root._class === "warning"
    urgent: root._class === "critical" || root._class === "urgent"
    tooltipText: root._tooltip

    function _run() {
        // `.length` truthiness, not Array.isArray: `module` crossed a
        // property assignment onto a Loader-created object (Bar.qml's
        // onLoaded), and the nested `command` array on the far side of that
        // boundary is a QVariantList — real, indexable, and perfectly
        // usable as Process.command, but Array.isArray() on it is false
        // (confirmed by reproducing it; silently starved _run() of ever
        // reaching proc.running = true).
        if (!root.module || !root.module.command || root.module.command.length === 0)
            return;
        if (proc.running)
            return;
        root._sawExit = false;
        proc.command = root.module.command;
        proc.running = true;
        timeoutTimer.restart();
    }

    function _applyState(state) {
        root._text = state.text;
        root._tooltip = state.tooltip;
        root._class = state["class"];
    }

    function _setError() {
        root._applyState(CommandOutput.errorState());
    }

    onModuleChanged: root._run()
    Component.onCompleted: root._run()

    Timer {
        id: pollTimer
        interval: root._interval
        running: root.module !== null
        repeat: true
        onTriggered: root._run()
    }

    // Single-shot per invocation, restarted by _run(). A command that
    // outlives this kills it (SIGTERM — Process.running's own documented
    // behavior) and reports the same error state rather than leaving a
    // stale value on screen indefinitely.
    Timer {
        id: timeoutTimer
        interval: root._timeout
        repeat: false
        onTriggered: {
            if (proc.running) {
                proc.running = false;
                root._setError();
            }
        }
    }

    Process {
        id: proc
        stdout: StdioCollector {
            id: stdoutCollector
        }
        onExited: exitCode => {
            root._sawExit = true;
            timeoutTimer.stop();
            root._applyState(CommandOutput.resolve(exitCode, stdoutCollector.text));
        }
        // quickshell's Process never emits `exited` when the command fails
        // to start (a missing/typo'd binary — process.cpp's
        // onErrorOccurred only emits runningChanged for FailedToStart), so
        // without this a bad command path left this cell blank forever
        // instead of erroring. `_sawExit` distinguishes that case from a
        // normal completion, where `exited` already fired first.
        onRunningChanged: {
            if (!proc.running && !root._sawExit) {
                timeoutTimer.stop();
                root._setError();
            }
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root._text
        color: root.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize.body
    }

    // Hover only: a command module has no click action of its own, so this
    // takes no buttons and leaves the cursor alone. It exists to drive the
    // tooltip above, and brings this cell's hover chrome in line with every
    // other bar cell while it's there.
    interactive: true
    acceptedButtons: Qt.NoButton
}

import QtQuick
import Quickshell.Io
import qs.Core
import qs.Components

// Bar cell for a `bar.modules[]` entry with type "command" (DESIGN.md
// §Bar, spec §Surfaces-1, M10 Task 3): runs `module.command` on an
// interval and parses its stdout as Waybar-JSON-compatible
// `{text, tooltip, class}`. `text` is the only field actually rendered —
// this shell has no established tooltip affordance yet, so `tooltip` is
// parsed and kept (future use) rather than shown. `class` maps onto the
// two states Cell already has (DESIGN's accent/urgent are flat blocks, not
// arbitrary CSS classes, so only "warning" and "critical"/"urgent" are
// recognised; anything else renders plain). A non-zero exit, a timeout, or
// output that fails to parse as JSON with a string `text` all render the
// same honest "MODULE ERROR" cell instead of a stale value.
Cell {
    id: root

    property var module: null

    readonly property int _interval: (root.module && root.module.interval > 0) ? root.module.interval : 5000
    readonly property int _timeout: (root.module && root.module.timeout > 0) ? root.module.timeout : 5000

    property string _text: ""
    property string _tooltip: ""
    property string _class: ""

    standalone: true
    accent: root._class === "warning"
    urgent: root._class === "critical" || root._class === "urgent"

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
        proc.command = root.module.command;
        proc.running = true;
        timeoutTimer.restart();
    }

    function _setError() {
        root._class = "";
        root._tooltip = "";
        root._text = "MODULE ERROR";
    }

    function _applyOutput(raw) {
        var parsed;
        try {
            parsed = JSON.parse(raw);
        } catch (e) {
            root._setError();
            return;
        }
        if (!parsed || typeof parsed.text !== "string") {
            root._setError();
            return;
        }
        root._text = parsed.text;
        root._tooltip = typeof parsed.tooltip === "string" ? parsed.tooltip : "";
        root._class = typeof parsed["class"] === "string" ? parsed["class"] : "";
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
            timeoutTimer.stop();
            if (exitCode !== 0) {
                root._setError();
                return;
            }
            root._applyOutput(stdoutCollector.text);
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root._text
        color: root.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.fontSize.body
    }
}

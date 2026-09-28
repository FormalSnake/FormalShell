pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Compositor
import "../Herdr/model.js" as HerdrModel

// herdr agent state, for the Spaces cell's per-window badges (M74 Task 1,
// plan at docs/superpowers/plans/2026-09-28-m74-spaces.md). herdr classifies
// every agent kind it knows itself (claude, codex, opencode, ...), so this
// reads `herdr agent list` rather than installing a hook or walking pids for
// one specific agent binary; a Claude session started outside herdr gets no
// badge, which is the honest answer, not a gap to work around.
//
// herdr's own API has no unscoped status-change event (`pane_agent_status_
// changed` needs a pane_id), so every client is polled on a plain 2s loop
// (Herdr/model.js's pollCommand), the same discipline dualsense-herdr
// already uses outside this repo. Which client a window even has is a
// separate, much slower-changing question, answered by walking `ps -eo
// pid=,ppid=,args=` down from that window's own pid whenever the window
// list changes (debounced): a client key only sticks around as a poller for
// as long as at least one window's subtree still resolves to it.
//
// No herdr on PATH, an unreachable remote, or a session herdr was never
// pointed at: all three read as "no client found" or a poller stuck at exit
// 127, and stateByWindow/stateByKey simply carry no entry for it. Nothing
// here fabricates a badge to fill the gap.
Singleton {
    id: root

    // window id -> "working" | "blocked" | "done". A window with nothing to
    // report is absent from the map, never an empty-string entry.
    property var stateByWindow: ({})
    // client key -> the same three values, one entry per key a window's
    // subtree currently resolves to.
    property var stateByKey: ({})

    // pid -> [key], from the last `ps` walk. Kept so a poll line landing
    // between two window-list ticks can still recompute stateByWindow off
    // the mapping that's still current.
    property var _keysByPid: ({})
    // key -> the titles its server renders under herdr's default
    // window_title (Herdr/model.js's defaultTitles), and the hostname and
    // labels they are built from. Only a window sharing its pid with others
    // needs these to be told apart (model.js's windowKeys).
    property var _titlesByKey: ({})
    property var _hostnameByKey: ({})
    property var _labelsByKey: ({})
    // key -> Process, one per client currently backed by at least one window.
    property var _pollers: ({})
    // key -> current backoff (ms) and the epoch ms a dead-but-wanted poller
    // may next be restarted at, both plain JS maps rather than a Timer per
    // poller: one shared ticker below walks them instead.
    property var _backoffMs: ({})
    property var _nextRetryAt: ({})

    readonly property int _baseBackoffMs: 2000
    readonly property int _maxBackoffMs: 60000

    readonly property var _windowPids: {
        var pids = [];
        var ws = CompositorService.windows;
        for (var i = 0; i < ws.length; i++) {
            var p = Number(ws[i].pid);
            if (isFinite(p) && p > 0)
                pids.push(p);
        }
        return pids;
    }

    // A burst of windows opening/closing at once (a session restoring
    // several terminals together) walks `ps` once, not once per window.
    Timer {
        id: _psDebounce
        interval: 400
        repeat: false
        onTriggered: root._runPsWalk()
    }

    // Hyprland's pid only arrives through `lastIpcObject`, which Quickshell
    // fills from `j/clients` on connect and on refreshToplevels alone, so a
    // window opened since startup reads pid 0 and its subtree is never
    // walked. One refresh per such window, not per tick: a window that still
    // has no pid after it would otherwise re-ask on every title change.
    property var _pidAsked: ({})

    Connections {
        target: CompositorService
        function onWindowsChanged() {
            var ws = CompositorService.windows;
            var ask = false;
            for (var i = 0; i < ws.length; i++) {
                if (!(Number(ws[i].pid) > 0) && !root._pidAsked[ws[i].id]) {
                    root._pidAsked[ws[i].id] = true;
                    ask = true;
                }
            }
            if (ask)
                CompositorService.refreshWindows();
            // A title change can settle a shared-pid window on its own, with
            // no process having come or gone.
            root._recomputeStateByWindow();
            _psDebounce.restart();
        }
    }

    Component.onCompleted: _psDebounce.restart()

    function _runPsWalk() {
        if (_psProc.running)
            return;
        _psProc.running = true;
    }

    Process {
        id: _psProc
        command: ["ps", "-eo", "pid=,ppid=,args="]
        stdout: StdioCollector {
            id: _psCollector
        }
        onExited: exitCode => root._applyPsWalk(exitCode, _psCollector.text)
    }

    function _applyPsWalk(exitCode, text) {
        // A `ps` that failed outright (missing binary, an odd container)
        // reads as "no clients anywhere" rather than leaving the last,
        // possibly stale, mapping in place.
        var rows = exitCode === 0 ? HerdrModel.parsePsRows(text) : [];
        var result = HerdrModel.clientsByWindow(rows, root._windowPids);
        root._keysByPid = result.byWindow;
        root._reconcilePollers(result.clients);
        root._recomputeStateByWindow();
    }

    // One poller per distinct client key: a plain `sh -c` loop for a local
    // `herdr`, an `ssh` round trip for `herdr --remote`. SplitParser hands
    // each `agent list` reply line to _onPollLine as it arrives; the loop
    // itself only ever exits on its own when herdr disappears from PATH (or
    // the ssh link dies), which is what onExited below treats as "dead,
    // retry with backoff" rather than "gone for good".
    Component {
        id: _pollerComponent
        Process {
            id: _poll
            property string clientKey: ""
            stdout: SplitParser {
                onRead: line => root._onPollLine(_poll.clientKey, line)
            }
            onExited: exitCode => root._onPollExited(_poll.clientKey)
        }
    }

    // Restarts a dead-but-still-wanted poller once its backoff has elapsed.
    // A single shared ticker rather than a Timer per poller: the interval
    // only needs to be fine enough to catch a just-elapsed backoff, not to
    // track it exactly.
    Timer {
        id: _retryTicker
        interval: 1000
        repeat: true
        running: Object.keys(root._pollers).length > 0
        onTriggered: root._retryDeadPollers()
    }

    function _retryDeadPollers() {
        var now = Date.now();
        for (var key in root._pollers) {
            var p = root._pollers[key];
            if (p.running)
                continue;
            var at = root._nextRetryAt[key];
            if (at === undefined || now < at)
                continue;
            p.running = true;
        }
    }

    function _onPollExited(key) {
        if (!root._pollers[key])
            return; // reconciliation already dropped this key
        var backoff = Math.min((root._backoffMs[key] || root._baseBackoffMs) * 2, root._maxBackoffMs);
        var backoffNext = Object.assign({}, root._backoffMs);
        backoffNext[key] = backoff;
        root._backoffMs = backoffNext;
        var retryNext = Object.assign({}, root._nextRetryAt);
        retryNext[key] = Date.now() + backoff;
        root._nextRetryAt = retryNext;
    }

    function _reconcilePollers(clients) {
        var key;
        for (key in root._pollers) {
            if (clients[key])
                continue;
            var dead = root._pollers[key];
            var pollersNext = Object.assign({}, root._pollers);
            delete pollersNext[key];
            root._pollers = pollersNext;
            var backoffNext = Object.assign({}, root._backoffMs);
            delete backoffNext[key];
            root._backoffMs = backoffNext;
            var retryNext = Object.assign({}, root._nextRetryAt);
            delete retryNext[key];
            root._nextRetryAt = retryNext;
            var stateNext = Object.assign({}, root.stateByKey);
            delete stateNext[key];
            root.stateByKey = stateNext;
            delete root._hostnameByKey[key];
            delete root._labelsByKey[key];
            var titlesNext = Object.assign({}, root._titlesByKey);
            delete titlesNext[key];
            root._titlesByKey = titlesNext;
            dead.destroy();
        }

        for (key in clients) {
            if (root._pollers[key])
                continue;
            var proc = _pollerComponent.createObject(root, {
                clientKey: key,
                command: HerdrModel.pollCommand(clients[key])
            });
            var added = Object.assign({}, root._pollers);
            added[key] = proc;
            root._pollers = added;
            proc.running = true;
        }
    }

    function _onPollLine(key, line) {
        if (!root._pollers[key])
            return; // a stale line from a poller reconciliation already dropped
        // Any line at all, including the poll loop's own `echo null` for a
        // failed call, proves the loop and its link are alive, so backoff
        // resets on it, not just on a successful parse.
        var backoffNext = Object.assign({}, root._backoffMs);
        backoffNext[key] = root._baseBackoffMs;
        root._backoffMs = backoffNext;

        var parsed = HerdrModel.parsePollLine(line);
        if (parsed.hostname !== undefined || parsed.labels !== undefined) {
            if (parsed.hostname !== undefined)
                root._hostnameByKey[key] = parsed.hostname;
            else
                root._labelsByKey[key] = parsed.labels;
            var titles = HerdrModel.defaultTitles(root._hostnameByKey[key], root._labelsByKey[key]);
            if ((root._titlesByKey[key] || []).join("\n") === titles.join("\n"))
                return;
            var titlesNext = Object.assign({}, root._titlesByKey);
            titlesNext[key] = titles;
            root._titlesByKey = titlesNext;
            root._recomputeStateByWindow();
            return;
        }
        var state = parsed.agents ? HerdrModel.aggregate(parsed.agents) : "";
        if (root.stateByKey[key] === state)
            return;
        var stateNext = Object.assign({}, root.stateByKey);
        stateNext[key] = state;
        root.stateByKey = stateNext;
        root._recomputeStateByWindow();
    }

    function _recomputeStateByWindow() {
        var out = {};
        var keys = HerdrModel.windowKeys(CompositorService.windows, root._keysByPid, root._titlesByKey);
        for (var id in keys) {
            var state = root.stateByKey[keys[id]];
            if (state)
                out[id] = state;
        }
        if (JSON.stringify(out) !== JSON.stringify(root.stateByWindow))
            root.stateByWindow = out;
    }
}

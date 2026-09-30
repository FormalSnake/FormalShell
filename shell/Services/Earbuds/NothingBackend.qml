import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "../../Earbuds/model.js" as Model
import "../../Earbuds/nothing.js" as Nothing

// Nothing and CMF devices behind the earbuds backend contract
// (EarbudsService.qml's header), over `nothingctl` (shell/Earbuds/nothing.js).
// Discovery is `nothingctl list --json`, run on acquire and whenever the set
// of connected Bluetooth devices changes. Each device it reports connected
// gets one `watch -d <addr>` child while held: a JSON line on stdout per
// change, one command per line on stdin. A device is listed only once its
// child has printed a state line.
//
// A device nothingctl refuses over its model prints one `unsupported-model`
// error line and exits 3 (nothingctl's README "Exit codes"). Retrying cannot
// change that answer, so the address is marked and left alone, never
// listed, until BlueZ reports it disconnected and then connected again.
// Every other exit (1 after `disconnected` when the link drops, or 1 with no
// line when the control service will not connect) drops the device and runs
// discovery again only after a backoff, starting at 5s and doubling up to 5
// minutes while the child keeps dying before its first state line. A
// restart needs `list` to report the device connected again.
Scope {
    id: root

    readonly property string name: Nothing.BACKEND
    // False only once `list` has failed to start: nothingctl ships on the
    // wrapper's PATH, so an unstarted one is a hand-built run.
    property bool available: true
    property var devices: []

    readonly property int _backoffMin: 5000
    readonly property int _backoffMax: 300000

    property bool _held: false
    property bool _listAgain: false
    // address -> watch Process, parsed state, failure line, retry { at, delay }.
    property var _watchers: ({})
    property var _states: ({})
    property var _failures: ({})
    property var _retry: ({})
    // address -> { seenDown }, kept across release so closing and reopening
    // the panel is not a way round it (Nothing.rearm).
    property var _unsupported: ({})

    // Live whether held or not: a refused device's disconnect has to be
    // seen even while nothing is showing the panel.
    readonly property var _btConnected: {
        var adapter = Bluetooth.defaultAdapter;
        var values = adapter ? adapter.devices.values : [];
        var out = [];
        for (var i = 0; i < values.length; i++)
            out.push({ address: values[i].address, name: values[i].name, deviceName: values[i].deviceName, connected: values[i].connected });
        return Model.bluetoothDevices(out, Quickshell.env("FORMALSHELL_SMOKE_BLUETOOTH")).filter(d => d.connected).map(d => d.address).sort();
    }

    on_BtConnectedChanged: {
        root._unsupported = Nothing.rearm(root._unsupported, root._btConnected);
        root._discover();
    }

    function acquire() {
        root._held = true;
        root._discover();
    }

    function release() {
        root._held = false;
        retryTimer.stop();
        root._listAgain = false;
        Object.keys(root._watchers).forEach(a => root._watchers[a].running = false);
        root._watchers = {};
        root._states = {};
        root._failures = {};
        root._retry = {};
        root.devices = [];
    }

    function set(deviceKey, controlKey, value) {
        var dev = root.devices.find(d => d.key === deviceKey);
        if (!dev)
            return false;
        var watcher = root._watchers[dev.address];
        var line = Nothing.command(controlKey, value, root._states[dev.address]);
        if (!watcher || !watcher.running || line === "")
            return false;
        // A range drag lands on the same whole value many times over; the
        // device already holds it, so nothing is written.
        var ctl = Model.control(dev, controlKey);
        if (ctl && (ctl.kind === "range" ? Math.round(ctl.value) : ctl.value) === value)
            return true;
        watcher.write(line + "\n");
        return true;
    }

    function _discover() {
        if (!root._held)
            return;
        if (listProc.running) {
            root._listAgain = true;
            return;
        }
        listProc.started = false;
        listProc.running = true;
    }

    function _onList(code, text) {
        if (!root._held)
            return;
        var now = Date.now();
        if (code === 0) {
            Nothing.parseList(text).forEach(d => {
                var retry = root._retry[d.address];
                if (!d.connected || root._watchers[d.address] || root._unsupported[d.address] || (retry && retry.at > now))
                    return;
                root._startWatch(d.address);
            });
        }
        if (root._listAgain) {
            root._listAgain = false;
            root._discover();
        }
    }

    function _startWatch(address) {
        var argv = Nothing.watchArgv(address);
        if (argv.length === 0)
            return;
        var p = _watchComponent.createObject(root, { address: address, command: argv });
        root._watchers[address] = p;
        p.running = true;
    }

    function _publish() {
        root.devices = Object.keys(root._states).sort().map(a => Nothing.normalise(root._states[a], root._failures[a] || ""));
    }

    function _onLine(address, line) {
        var msg = Nothing.parseLine(line);
        if (!msg || !root._held)
            return;
        if (msg.type === "state" && msg.state.address === address) {
            root._states[address] = msg.state;
            delete root._failures[address];
            delete root._retry[address];
        } else if (msg.type === "ack") {
            delete root._failures[address];
        } else if (msg.type === "error" && msg.code === Nothing.UNSUPPORTED) {
            root._markUnsupported(address, msg.message);
            return;
        } else if (msg.type === "error") {
            console.warn("nothingctl " + address + ": " + msg.message);
            root._failures[address] = Nothing.FAILED;
        } else if (msg.type === "disconnected") {
            delete root._states[address];
            delete root._failures[address];
        } else {
            return;
        }
        root._publish();
    }

    function _markUnsupported(address, message) {
        if (root._unsupported[address])
            return;
        console.warn("nothingctl " + address + ": " + (message || "unsupported model") + "; not retried until it reconnects");
        var next = Object.assign({}, root._unsupported);
        next[address] = { seenDown: false };
        root._unsupported = next;
    }

    // code: the exit code, or -1 for a child that never started.
    function _onExit(p, code) {
        if (p.done)
            return;
        p.done = true;
        var address = p.address;
        if (root._watchers[address] === p)
            delete root._watchers[address];
        p.destroy();
        if (code === Nothing.UNSUPPORTED_EXIT)
            root._markUnsupported(address, "");
        if (!root._held)
            return;
        delete root._states[address];
        delete root._failures[address];
        root._publish();
        if (root._unsupported[address])
            return;
        var last = root._retry[address];
        var delay = last ? Math.min(last.delay * 2, root._backoffMax) : root._backoffMin;
        root._retry[address] = { at: Date.now() + delay, delay: delay };
        root._armRetry();
    }

    function _armRetry() {
        var now = Date.now();
        var next = -1;
        Object.keys(root._retry).forEach(a => {
            var at = root._retry[a].at;
            if (at > now && (next < 0 || at < next))
                next = at;
        });
        if (next < 0)
            return;
        retryTimer.interval = Math.max(1, next - now);
        retryTimer.restart();
    }

    Timer {
        id: retryTimer
        onTriggered: {
            root._discover();
            root._armRetry();
        }
    }

    Process {
        id: listProc
        property bool started: false
        command: Nothing.listArgv()
        stdout: StdioCollector {
            id: listOut
        }
        onStarted: {
            listProc.started = true;
            root.available = true;
        }
        onExited: code => root._onList(code, listOut.text)
        onRunningChanged: {
            if (!listProc.running && !listProc.started) {
                root.available = false;
                root._onList(-1, "");
            }
        }
    }

    Component {
        id: _watchComponent
        Process {
            id: w
            property string address: ""
            property bool started: false
            property bool done: false
            stdinEnabled: true
            stdout: SplitParser {
                onRead: line => root._onLine(w.address, line)
            }
            stderr: SplitParser {
                onRead: line => console.warn("nothingctl " + w.address + ": " + line)
            }
            onStarted: w.started = true
            onExited: code => root._onExit(w, code)
            onRunningChanged: {
                if (!w.running && !w.started)
                    root._onExit(w, -1);
            }
        }
    }
}

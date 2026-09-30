import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "../../Earbuds/model.js" as Model

// The poll half of the earbuds backend contract (EarbudsService.qml's
// header), shared by the CLI-driven backends. A vendor file instantiates
// this, sets `name`, and answers `poll()` by chaining run() calls and
// finishing with pollDone(); it publishes what it found in `devices`.
//
// Nothing runs outside acquire()/release(): the timer, every child and the
// Bluetooth snapshot all stop with the last consumer. `poll()` fires on the
// timer and whenever the set of connected Bluetooth devices changes (which
// includes the snapshot appearing on acquire), since a pair of buds that just
// connected should not wait out the interval. Commands run one at
// a time, in order: a CLI that owns a device link (an RFCOMM socket, a
// daemon) is not asked to serve two calls at once.
//
// A child that cannot start (no binary on PATH) never emits `exited`, only
// a `running` flip, so that case is reported to done() as code -1.
Scope {
    id: root

    property string name: ""
    // False only once a command has failed to start: the CLIs ship on the
    // wrapper's PATH, so an unstarted one is a hand-built run.
    property bool available: true
    property var devices: []
    property int interval: 30000

    // Connected or not, every device BlueZ knows: { address, name,
    // deviceName, connected }. Empty while not held.
    readonly property var bluetooth: root._held ? root._snapshot() : []
    readonly property string _btKey: JSON.stringify(root.bluetooth.filter(d => d.connected).map(d => d.address).sort())

    signal poll

    property bool _held: false
    property bool _polling: false
    property bool _again: false
    property int _generation: 0
    property var _jobs: []
    property bool _busy: false

    // Read here rather than inside the helper, so the binding above tracks
    // every device's `connected`.
    function _snapshot() {
        var adapter = Bluetooth.defaultAdapter;
        var values = adapter ? adapter.devices.values : [];
        var out = [];
        for (var i = 0; i < values.length; i++) {
            var d = values[i];
            out.push({ address: d.address, name: d.name, deviceName: d.deviceName, connected: d.connected });
        }
        return Model.bluetoothDevices(out, Quickshell.env("FORMALSHELL_SMOKE_BLUETOOTH"));
    }

    function acquire() {
        root._held = true;
        timer.start();
    }

    function release() {
        root._held = false;
        timer.stop();
        root._generation++;
        root._jobs = [];
        root._polling = false;
        root._again = false;
    }

    // A poll already in flight is followed by one more, so a write's effect
    // is never read from a poll that began before it.
    function requestPoll() {
        if (!root._held)
            return;
        if (root._polling) {
            root._again = true;
            return;
        }
        root._polling = true;
        root.poll();
    }

    function pollDone() {
        root._polling = false;
        if (root._again && root._held) {
            root._again = false;
            root.requestPoll();
        }
    }

    // argv: an array, never a shell string. done(exitCode, stdout) runs once,
    // unless release() came first; an empty argv (an adapter refusing to
    // build one) answers -2 at once.
    function run(argv, done) {
        if (!root._held)
            return;
        if (argv.length === 0) {
            done(-2, "");
            return;
        }
        root._jobs = root._jobs.concat([{ argv: argv, done: done, generation: root._generation }]);
        root._pump();
    }

    function _pump() {
        if (root._busy || root._jobs.length === 0)
            return;
        var job = root._jobs[0];
        root._jobs = root._jobs.slice(1);
        root._busy = true;
        var p = _jobComponent.createObject(root, { job: job, command: job.argv });
        p.running = true;
    }

    function _finish(p, code, text) {
        if (p.finished)
            return;
        p.finished = true;
        root._busy = false;
        root.available = code !== -1;
        if (p.job.generation === root._generation)
            p.job.done(code, text);
        p.destroy();
        root._pump();
    }

    Timer {
        id: timer
        interval: root.interval
        repeat: true
        onTriggered: root.requestPoll()
    }

    on_BtKeyChanged: root.requestPoll()

    Component {
        id: _jobComponent
        Process {
            id: p
            property var job: null
            property bool started: false
            property bool finished: false
            stdout: StdioCollector {
                id: out
            }
            onStarted: p.started = true
            onExited: code => root._finish(p, code, out.text)
            onRunningChanged: {
                if (!p.running && !p.started)
                    root._finish(p, -1, "");
            }
        }
    }
}

import QtQuick
import "../../Earbuds/samsung.js" as Samsung

// Samsung Galaxy Buds behind the earbuds backend contract
// (EarbudsService.qml's header), over `earbuds` (shell/Earbuds/samsung.js).
// The CLI starts its own daemon on any command, so nothing is run unless
// BlueZ reports a device with a Galaxy Buds name connected, and the daemon
// is never stopped from here: it is the user's to keep or kill.
PollingBackend {
    id: root

    name: Samsung.BACKEND

    function set(deviceKey, controlKey, value) {
        var dev = root.devices.find(d => d.key === deviceKey);
        if (!dev)
            return false;
        var tail = Samsung.command(controlKey, value);
        var argv = Samsung.argv(dev.address, tail);
        if (tail.length === 0 || argv.length === 0)
            return false;
        root.run(argv, () => root.requestPoll());
        return true;
    }

    onPoll: root._readNext(Samsung.connectedBuds(root.bluetooth), [])

    function _readNext(targets, found) {
        if (targets.length === 0) {
            root.devices = found;
            root.pollDone();
            return;
        }
        var buds = targets[0];
        var rest = targets.slice(1);
        root.run(Samsung.statusArgv(buds.address), (code, text) => {
            root._readNext(rest, found.concat(code === 0 ? Samsung.normalise(Samsung.parseStatus(text), buds.name) : []));
        });
    }
}

import QtQuick
import "../../Earbuds/soundcore.js" as Soundcore

// Soundcore behind the earbuds backend contract (EarbudsService.qml's
// header), over `openscq30` (shell/Earbuds/soundcore.js). Each poll reads
// the CLI's own paired list, keeps the entries BlueZ reports connected, and
// reads their settings; nothing is spawned while no Bluetooth device is
// connected. Every openscq30 call opens its own link to the device, so a
// device's settings list is read once per connection and kept, and a poll
// is one `--get` call per device.
PollingBackend {
    id: root

    name: Soundcore.BACKEND

    // address -> capabilities, dropped when the device stops being connected
    // so a reconnect (a firmware update can change the list) reads it again.
    property var _caps: ({})

    function set(deviceKey, controlKey, value) {
        var dev = root.devices.find(d => d.key === deviceKey);
        if (!dev)
            return false;
        var tail = Soundcore.command(controlKey, value, root._caps[dev.address]);
        var argv = Soundcore.settingArgv(dev.address, tail);
        if (tail.length === 0 || argv.length === 0)
            return false;
        root.run(argv, () => root.requestPoll());
        return true;
    }

    onPoll: {
        if (!root.bluetooth.some(d => d.connected)) {
            root._caps = {};
            root.devices = [];
            root.pollDone();
            return;
        }
        root.run(Soundcore.pairedArgv(), (code, text) => {
            var targets = code === 0 ? Soundcore.connectedPaired(Soundcore.parsePaired(text), root.bluetooth) : [];
            var keep = {};
            targets.forEach(t => keep[t.address] = true);
            Object.keys(root._caps).forEach(a => {
                if (!keep[a])
                    delete root._caps[a];
            });
            root._readNext(targets, []);
        });
    }

    function _readNext(targets, found) {
        if (targets.length === 0) {
            root.devices = found;
            root.pollDone();
            return;
        }
        var info = targets[0];
        var rest = targets.slice(1);
        var caps = root._caps[info.address];
        if (caps) {
            root._read(info, caps, rest, found);
            return;
        }
        root.run(Soundcore.settingsArgv(info.address), (code, text) => {
            var parsed = code === 0 ? Soundcore.parseCapabilities(text) : null;
            if (!parsed) {
                root._readNext(rest, found);
                return;
            }
            root._caps[info.address] = parsed;
            root._read(info, parsed, rest, found);
        });
    }

    function _read(info, caps, rest, found) {
        var argv = Soundcore.settingArgv(info.address, Soundcore.getArgs(caps));
        root.run(caps.ids.length > 0 ? argv : [], (code, text) => {
            root._readNext(rest, found.concat([Soundcore.normalise(info, caps, code === 0 ? Soundcore.parseValues(text) : {})]));
        });
    }
}

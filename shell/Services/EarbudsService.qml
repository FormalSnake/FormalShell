pragma Singleton
import QtQuick
import Quickshell
import "Earbuds"
import "../Earbuds/model.js" as Model

// Every connected pair of earbuds or headphones, across vendors, in the one
// shape shell/Earbuds/model.js defines (spec
// docs/superpowers/specs/2026-09-30-m77-earbuds.md). The panel, bar cell and
// IPC read only this; none of them knows a vendor.
//
// A backend is one object in `backends` below with:
//   name: string                 the adapter's BACKEND id
//   available: bool              its source exists (daemon up, CLI on PATH)
//   devices: [device]            normalised by its shell/Earbuds/<vendor>.js
//   acquire() / release()        called once as the first consumer arrives
//                                and the last one leaves; nothing polls,
//                                watches or runs a child outside that window
//   set(deviceKey, controlKey, value): bool
//                                value already coerced to the control's type
//                                (Model.coerce); the backend turns it into
//                                its own command through the adapter's
//                                allow-list and returns false on refusal
// A file-watch backend reloads on acquire (AirpodsBackend). A process
// backend starts its long-running child per device on acquire, parses each
// stdout line through the adapter into `devices`, writes the adapter's
// command line to stdin in set(), and stops the children on release. A
// poll backend runs a Timer between acquire and release and one short
// Process per set().
Singleton {
    id: root

    readonly property var backends: [airpods, nothing, soundcore, samsung]

    AirpodsBackend { id: airpods }
    NothingBackend { id: nothing }
    SoundcoreBackend { id: soundcore }
    SamsungBackend { id: samsung }

    readonly property bool available: root.backends.some(b => b.available)
    readonly property var devices: {
        var out = [];
        root.backends.forEach(b => out = out.concat(b.devices));
        return out;
    }
    readonly property var active: Model.pickActive(root.devices, root._activeKey)

    // The user's last pick, overwritten whenever a device newly connects, so
    // the panel follows whatever was put in last.
    property string _activeKey: ""
    property var _wasConnected: ({})

    onDevicesChanged: {
        var now = {};
        root.devices.forEach(d => {
            now[d.key] = d.connected;
            if (d.connected && !root._wasConnected[d.key])
                root._activeKey = d.key;
        });
        root._wasConnected = now;
    }

    function select(key) {
        for (var i = 0; i < root.devices.length; i++) {
            if (root.devices[i].key === key) {
                root._activeKey = key;
                return true;
            }
        }
        return false;
    }

    // Against the active device. Returns "" on success or the reason it was
    // refused, which the IPC hands back verbatim.
    function set(controlKey, raw) {
        var dev = root.active;
        if (!dev)
            return "no device";
        var ctl = Model.control(dev, controlKey);
        if (!ctl)
            return "no control '" + controlKey + "' on " + dev.name;
        var value = Model.coerce(ctl, raw);
        if (value === undefined)
            return "refused '" + raw + "' for " + controlKey;
        var backend = root.backends.find(b => b.name === dev.backend);
        if (!backend || !backend.set(dev.key, controlKey, value))
            return "refused by " + dev.backend;
        return "";
    }

    property int _refCount: 0

    function acquire() {
        root._refCount++;
        if (root._refCount === 1)
            root.backends.forEach(b => b.acquire());
    }

    function release() {
        if (root._refCount === 0)
            return;
        root._refCount--;
        if (root._refCount === 0)
            root.backends.forEach(b => b.release());
    }
}

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Compositor
import qs.Core as Core
import "../Display/hdr.js" as Hdr
import "../Display/outputs.js" as Outputs

// Per-output HDR. Whether an output can do it comes from its EDID
// (Display/hdr.js has the why), read once per set of connector names off
// /sys/class/drm. The choice lives in Core.State.hdr, never settings.json,
// and is re-applied whenever an output that should be in HDR shows up
// without it: shell start, hotplug, and a config reload that reset the rules
// (a reload re-runs the Lua config, which drops a rule sent through eval).
//
// Each output is re-applied at most once per reset. An apply Hyprland ignores
// leaves the output out of HDR and would otherwise retry on every refresh.
//
// `display.hdr.sdrBrightness` (default 1.2) and `display.hdr.sdrSaturation`
// (default 1) are the SDR level while HDR is on; at 1.0 SDR windows read dim
// next to the panel's HDR white.
Singleton {
    id: root

    readonly property var _backend: CompositorService.backend
    readonly property var _rows: root._backend.outputs
    readonly property var wanted: Hdr.stateOf(Core.State.hdr)

    // { name: parseEdid() } for the connector names last asked about.
    property var _edids: ({})
    property string _edidNames: ""
    property bool _edidRead: false

    readonly property var verdicts: {
        var out = {};
        for (var i = 0; i < root._rows.length; i++) {
            var name = root._rows[i].name;
            out[name] = root._edidRead ? Hdr.verdict(root._edids[name]) : { supported: false, reason: "Checking" };
        }
        return out;
    }

    readonly property bool active: {
        for (var i = 0; i < root._rows.length; i++) {
            if (Hdr.isOn(root._rows[i]))
                return true;
        }
        return false;
    }

    readonly property real _sdrBrightness: Core.Config.get("display.hdr.sdrBrightness", 1.2)
    readonly property real _sdrSaturation: Core.Config.get("display.hdr.sdrSaturation", 1)

    property var _tried: ({})

    function _row(name) {
        return Outputs.findOutput(root._rows, name);
    }

    function supported(name) {
        var v = root.verdicts[name];
        return !!v && v.supported;
    }

    // The dim line under an output that cannot do HDR; "" when it can.
    function reason(name) {
        var v = root.verdicts[name];
        return v ? v.reason : "";
    }

    function isOn(name) {
        return Hdr.isOn(root._row(name));
    }

    function _supportedNames() {
        var names = [];
        for (var i = 0; i < root._rows.length; i++) {
            if (root._rows[i].enabled && root.supported(root._rows[i].name))
                names.push(root._rows[i].name);
        }
        return names;
    }

    function _apply(row, color) {
        root._backend.setOutputColor(row.name, color);
    }

    // "ok" or the reason nothing was done.
    function set(name, on) {
        if (!root._backend.outputConfigAvailable)
            return "no compositor";
        var row = root._row(name);
        if (!row)
            return "unknown output: " + name;
        if (!row.enabled)
            return name + " is disabled";
        if (on && !root.supported(name))
            return "HDR unavailable on " + name + ": " + root.reason(name);

        var saved = root.wanted[name];
        var prior = saved && saved.prior ? saved.prior : Hdr.priorOf(row);
        if (on) {
            Core.State.setHdr(Hdr.withOutput(root.wanted, name, prior));
            root._tried[name] = true;
            root._apply(row, Hdr.onColor(root._sdrBrightness, root._sdrSaturation));
        } else {
            Core.State.setHdr(Hdr.withoutOutput(root.wanted, name));
            if (Hdr.isOn(row))
                root._apply(row, Hdr.offColor(prior));
        }
        return "ok";
    }

    // Every output that can do HDR flips together: on unless one is already
    // in HDR, then all off. Errors when nothing can.
    function setAll(on) {
        var names = root._supportedNames();
        if (names.length === 0)
            return on ? "no output supports HDR" : "ok";
        for (var i = 0; i < names.length; i++)
            root.set(names[i], on);
        return "ok";
    }

    function toggle() {
        var names = root._supportedNames();
        if (names.length === 0)
            return "no output supports HDR";
        var anyOn = names.some(function (n) { return root.isOn(n); });
        return root.setAll(!anyOn);
    }

    function statusJson() {
        var outputs = root._rows.map(function (row) {
            return {
                name: row.name,
                supported: root.supported(row.name),
                reason: root.reason(row.name),
                on: Hdr.isOn(row),
                wanted: root.wanted[row.name] !== undefined,
                cm: row.cm
            };
        });
        return JSON.stringify({ active: root.active, outputs: outputs });
    }

    // The rule set() would send for `name`, without sending it.
    function ruleJson(name) {
        var row = root._row(name);
        if (!row)
            return "unknown output: " + name;
        var rule = Outputs.hyprlandColorRule(row, Hdr.onColor(root._sdrBrightness, root._sdrSaturation));
        return JSON.stringify({ rule: rule, lua: Outputs.hyprlandRuleLua(rule) });
    }

    function _reconcile() {
        var names = Hdr.pendingReapply(Core.State.hdr, root._rows, root.verdicts, root._tried);
        for (var i = 0; i < names.length; i++) {
            root._tried[names[i]] = true;
            root._apply(root._row(names[i]), Hdr.onColor(root._sdrBrightness, root._sdrSaturation));
        }
    }

    on_RowsChanged: {
        var names = root._rows.map(function (r) { return r.name; }).sort().join("\n");
        if (names !== root._edidNames && names !== "") {
            root._edidNames = names;
            edidProc.command = ["sh", "-c",
                "for n in \"$@\"; do for f in /sys/class/drm/card*-\"$n\"/edid; do [ -r \"$f\" ] || continue; echo \"@@$n\"; od -An -tx1 -v \"$f\"; done; done",
                "sh"].concat(names.split("\n"));
            edidProc.running = true;
        }
        var live = {};
        for (var i = 0; i < root._rows.length; i++)
            live[root._rows[i].name] = true;
        for (var name in root._tried) {
            if (!live[name])
                delete root._tried[name];
        }
        root._reconcile();
    }

    onVerdictsChanged: root._reconcile()
    Connections {
        target: Core.State
        function onHdrChanged() { root._reconcile(); }
    }

    Connections {
        target: root._backend
        ignoreUnknownSignals: true
        function onConfigReloaded() { root._tried = ({}); }
    }

    Process {
        id: edidProc
        stdout: StdioCollector {
            id: edidOut
        }
        onExited: {
            root._edids = Hdr.parseDump(edidOut.text);
            root._edidRead = true;
        }
    }
}

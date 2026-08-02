import Quickshell.Io
import Quickshell.Networking

import "../Network/model.js" as NetworkModel

// `qs ipc call network status|connect|connectEap|forget|wifi` — spec
// addendum (the `panel` tradition, CLAUDE.md hard rules): drives the wifi
// flow headlessly for the hwsim rig (nix/testvm.nix's FORMALTEST/
// FORMALTEST-EAP radios) and gives compositor keybinds a target `panel
// toggle network` alone can't (a bind that should also join a saved
// network). Unknown ssid -> error string, never a silent no-op.
//
// connect/connectEap/forget drive NetworkPanel.qml's OWN row-activation
// methods (same pattern CalendarIpc drives CalendarPanel's selectIsoDate)
// rather than calling Quickshell.Networking directly: the panel's failure
// handling (wifiRow's Connections.onConnectionFailed -> _failAction) is
// gated on root._actionKind having been armed by _runAction first — an IPC
// call that skipped straight to network.connectWithPsk() left that gate
// permanently closed, so a genuine wrong-password rejection produced a
// correctly-settled disconnected state but never lit up the row's WRONG
// PASSWORD text (reproduced: wifi-wrong.png showed a bare unconnected row
// even though wpa_supplicant's own journal showed a real 4-way-handshake
// failure). Routing through the panel's real methods means an IPC-driven
// connect renders exactly what an interactive click would.
IpcHandler {
    target: "network"

    // Set from shell.qml — the single NetworkPanel instance.
    property var panel: null

    function _wifiNetworks() {
        var out = [];
        var devices = Networking.devices.values;
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].type !== DeviceType.Wifi)
                continue;
            var networks = devices[i].networks.values;
            for (var j = 0; j < networks.length; j++)
                out.push(networks[j]);
        }
        return out;
    }

    function _findNetwork(ssid) {
        var networks = _wifiNetworks();
        for (var i = 0; i < networks.length; i++) {
            if ((networks[i].name || "") === ssid)
                return networks[i];
        }
        return null;
    }

    // Compact status for the smoke rig's poll loop: wifi radio power plus
    // one row per known/visible network. stateChanging rides alongside
    // connected so a caller can poll until NM has actually settled
    // (succeeded or given up) instead of guessing a sleep.
    function status(): string {
        var networks = _wifiNetworks().map(function (n) {
            return {
                name: n.name || "",
                known: n.known,
                connected: n.connected,
                stateChanging: n.stateChanging,
                secured: NetworkModel.isSecured(n.security),
                signal: n.signalStrength
            };
        });
        return JSON.stringify({ wifiEnabled: Networking.wifiEnabled, networks: networks });
    }

    function connect(ssid: string, psk: string): string {
        if (!panel)
            return "error: network panel not ready";
        var network = _findNetwork(ssid);
        if (!network)
            return "error: unknown ssid '" + ssid + "'";
        if (psk === "") {
            panel._activateWifiRow(network);
            return "ok";
        }
        panel._openPasswordPrompt(ssid);
        panel._passwordText = psk;
        panel._submitPassword(network);
        return "ok";
    }

    function connectEap(ssid: string, identity: string, password: string): string {
        if (!panel)
            return "error: network panel not ready";
        var network = _findNetwork(ssid);
        if (!network)
            return "error: unknown ssid '" + ssid + "'";
        panel._openPasswordPrompt(ssid);
        panel._identityText = identity;
        panel._passwordText = password;
        panel._submitPassword(network);
        return "ok";
    }

    function forget(ssid: string): string {
        if (!panel)
            return "error: network panel not ready";
        var network = _findNetwork(ssid);
        if (!network)
            return "error: unknown ssid '" + ssid + "'";
        panel._forgetNetwork(network);
        return "ok";
    }

    function wifi(enabled: bool): string {
        Networking.wifiEnabled = enabled;
        return "ok";
    }
}

import Quickshell.Io
import Quickshell.Networking
import qs.Services

import "../Network/model.js" as NetworkModel

// `qs ipc call network status|connect|connectEap|forget|wifi`, spec
// addendum (the `panel` tradition, CLAUDE.md hard rules): drives the wifi
// flow headlessly for the hwsim rig (nix/testvm.nix's FORMALTEST/
// FORMALTEST-EAP radios) and gives compositor keybinds a target `panel
// toggle network` alone can't (a bind that should also join a saved
// network). Unknown ssid -> error string, never a silent no-op.
//
// connect/connectEap/forget go through WifiService, the same actions the
// panel and the launcher run. The failure handling (Connections.
// onConnectionFailed -> failAction) is gated on the service's actionKind
// having been armed by runAction first: a call that skipped straight to
// network.connectWithPsk() left that gate closed, so a genuine wrong-password
// rejection settled to a bare disconnected row with no failure text.
IpcHandler {
    target: "network"

    // Set from shell.qml: the NetworkPanel's PanelSlot, built on first use.
    // Only the speed test verbs need it; the speed test lives on the panel.
    property var panel: null

    // Compact status for the smoke rig's poll loop: wifi radio power plus
    // one row per known/visible network. stateChanging rides alongside
    // connected so a caller can poll until NM has actually settled
    // (succeeded or given up) instead of guessing a sleep.
    function status(): string {
        var networks = WifiService.wifiNetworks().map(function (n) {
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

    // A network action already in flight is not a condition the verbs below
    // can proceed past: the service refuses to start a second one, and an
    // honest error beats a silent no-op.
    function _busyError() {
        return "error: network action already in progress (" + WifiService.actionKind + " " + WifiService.actionSsid + ")";
    }

    function connect(ssid: string, psk: string): string {
        if (WifiService.actionKind !== "")
            return _busyError();
        var network = WifiService.findNetwork(ssid);
        if (!network)
            return "error: unknown ssid '" + ssid + "'";
        if (psk === "") {
            if (WifiService.activate(network) === "needsSecret")
                return "error: '" + ssid + "' needs a password";
        } else {
            WifiService.connectPsk(network, psk);
        }
        return "ok";
    }

    function connectEap(ssid: string, identity: string, password: string): string {
        if (WifiService.actionKind !== "")
            return _busyError();
        var network = WifiService.findNetwork(ssid);
        if (!network)
            return "error: unknown ssid '" + ssid + "'";
        WifiService.connectEnterprise(network, identity, password);
        return "ok";
    }

    function forget(ssid: string): string {
        if (WifiService.actionKind !== "")
            return _busyError();
        var network = WifiService.findNetwork(ssid);
        if (!network)
            return "error: unknown ssid '" + ssid + "'";
        WifiService.forget(network);
        return "ok";
    }

    function wifi(enabled: bool): string {
        WifiService.setEnabled(enabled);
        return "ok";
    }

    // Speed test verbs (M16 Task 9): drive NetworkPanel's own
    // _startSpeedTest()/state, the same "route through the panel's real
    // methods" rationale as connect/connectEap/forget above, so a headless
    // run renders exactly what clicking RUN would.
    function speedtest(): string {
        var p = panel ? panel.load() : null;
        if (!p)
            return "error: network panel not ready";
        if (p._stRunning)
            return "error: speed test already running";
        p._startSpeedTest();
        return "ok";
    }

    function speedstatus(): string {
        var p = panel ? panel.load() : null;
        if (!p)
            return "error: network panel not ready";
        var downMbps = p._stPhase === "down" ? p._stDownWindow.liveMbps : p._stDownResult;
        var upMbps = p._stPhase === "up" ? p._stUpWindow.liveMbps : p._stUpResult;
        return JSON.stringify({
            running: p._stRunning,
            phase: p._stPhase,
            downMbps: downMbps,
            upMbps: upMbps,
            error: p._stError
        });
    }
}

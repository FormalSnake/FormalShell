pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../Network/model.js" as NetworkModel

// Wi-Fi actions and their bookkeeping, shared by NetworkPanel, NetworkIpc and
// the launcher's wifi route. Bound directly to Quickshell.Networking.
//
// One action is in flight at a time (omarchy's runNetworkAction/actionKind
// pattern): actionKind is "connect" | "disconnect" | "forget" | "" while
// idle. The failure handling is armed by runAction: a connectionFailed that
// arrives with no action in flight is ignored, so every caller has to start
// its action through here, or a genuine wrong-password rejection settles to
// a bare disconnected row with no failure text. The per-network Connections
// live in this singleton rather than in a panel row so a connect started
// with the panel closed still settles.
//
// The wifi device's `scannerEnabled` follows the set of holders (the panel
// while open, the launcher while its wifi level is up): a live list while
// someone looks, an idle radio otherwise.
//
// EAP profile creation shells out to nmcli. The password never touches
// argv: it arrives over the Process's own stdin, read by `IFS= read -r pw`
// and fed straight into nmcli's scriptable `connection edit` editor. Command
// shape mirrored from omarchy's enterpriseConnectScript
// (~/Developer/omarchy/shell/plugins/panels/network/Model.js:322-333) with
// one addition: the leading `command -v` guard, so a missing nmcli reads as
// exit 127 rather than as a generic connect failure.
Singleton {
    id: root

    property string actionSsid: ""
    property string actionKind: ""
    property string failureSsid: ""
    property string failureText: ""
    property int failureReason: -1
    // NetworkManager answers a rejected passphrase with NoSecrets, the same
    // reason it gives when it never had one. When this attempt carried a
    // secret, the rejection is what "Wrong password" means.
    property bool _secretSupplied: false

    // Emitted when a connect settles or is abandoned, so a panel prompt
    // waiting on it can close.
    signal connectSettled()
    // NoSecrets arrived for a network the caller did not hand a secret to.
    signal secretRequired(string ssid)

    readonly property var devices: Networking.devices.values.filter(function (d) { return d.type === DeviceType.Wifi; })
    readonly property bool hasDevice: root.devices.length > 0
    readonly property bool enabled: Networking.wifiEnabled

    readonly property var networks: {
        var out = [];
        for (var i = 0; i < root.devices.length; i++) {
            var list = root.devices[i].networks.values;
            for (var j = 0; j < list.length; j++)
                out.push(list[j]);
        }
        return out;
    }

    readonly property string connectedSsid: {
        for (var i = 0; i < root.networks.length; i++) {
            if (root.networks[i].connected)
                return root.networks[i].name || "";
        }
        return "";
    }

    function setEnabled(on) {
        Networking.wifiEnabled = on;
    }

    function wifiNetworks() {
        return root.networks;
    }

    function findNetwork(ssid) {
        for (var i = 0; i < root.networks.length; i++) {
            if ((root.networks[i].name || "") === ssid)
                return root.networks[i];
        }
        return null;
    }

    // ---- Scanning --------------------------------------------------------

    property var _scanHolders: ({})

    function holdScan(holder, on) {
        var next = Object.assign({}, root._scanHolders);
        if (on)
            next[holder] = true;
        else
            delete next[holder];
        root._scanHolders = next;
        root._applyScanner();
    }

    function _applyScanner() {
        var want = Object.keys(root._scanHolders).length > 0;
        for (var i = 0; i < root.devices.length; i++)
            root.devices[i].scannerEnabled = want;
    }

    onDevicesChanged: root._applyScanner()

    // Quickshell.Networking exposes no rescan call at all (checked against
    // quickshell-network.qmltypes: WifiDevice carries `scannerEnabled` and
    // nothing else), so dropping the scanner and re-arming it is the only
    // rescan handle the binding gives.
    function rescan() {
        for (var i = 0; i < root.devices.length; i++)
            root.devices[i].scannerEnabled = false;
        Qt.callLater(root._applyScanner);
    }

    // ---- Actions ---------------------------------------------------------

    function runAction(kind, network) {
        if (root.actionKind !== "" || !network)
            return false;
        root.actionSsid = network.name || "";
        root.actionKind = kind;
        root.failureSsid = "";
        root.failureText = "";
        root.failureReason = -1;
        root._secretSupplied = false;
        actionTimeout.restart();
        return true;
    }

    function clearAction() {
        actionTimeout.stop();
        var wasConnect = root.actionKind === "connect";
        root.actionSsid = "";
        root.actionKind = "";
        root.failureSsid = "";
        root.failureText = "";
        root.failureReason = -1;
        if (wasConnect)
            root.connectSettled();
    }

    function checkActionCompletion(network) {
        if (!network || root.actionKind === "" || root.actionSsid !== (network.name || ""))
            return;
        if (root.actionKind === "connect" && network.connected) root.clearAction();
        else if (root.actionKind === "disconnect" && !network.connected && !network.stateChanging) root.clearAction();
        else if (root.actionKind === "forget" && !network.known && !network.stateChanging) root.clearAction();
    }

    function failAction(network, reason) {
        if (!network || root.actionKind === "" || root.actionSsid !== (network.name || ""))
            return;
        actionTimeout.stop();
        if (reason === NetworkModel.ConnectionFailReason.NoSecrets && root._secretSupplied)
            reason = NetworkModel.ConnectionFailReason.WifiAuthTimeout;
        root.failureSsid = root.actionSsid;
        root.failureText = NetworkModel.failureText(reason);
        root.failureReason = reason;
        root.actionSsid = "";
        root.actionKind = "";
        if (reason === NetworkModel.ConnectionFailReason.NoSecrets)
            root.secretRequired(network.name || "");
    }

    // Connected -> disconnect. A secured network nobody knows, or one whose
    // last attempt failed on the secret, answers "needsSecret" and does
    // nothing, so a wrong password is retyped rather than retried. Anything
    // else connects with the saved secrets. "busy" while another action runs.
    function activate(network) {
        if (!network || root.actionKind !== "")
            return "busy";
        if (network.connected) {
            if (root.runAction("disconnect", network))
                network.disconnect();
            return "ok";
        }
        var ssid = network.name || "";
        var retypeSecret = root.failureSsid === ssid && NetworkModel.isSecretFailure(root.failureReason);
        if (retypeSecret || (NetworkModel.isSecured(network.security) && !network.known))
            return "needsSecret";
        if (root.runAction("connect", network))
            network.connect();
        return "ok";
    }

    function connectPsk(network, psk) {
        if (!network || root.actionKind !== "" || psk.length === 0)
            return false;
        if (!root.runAction("connect", network))
            return false;
        root._secretSupplied = true;
        network.connectWithPsk(psk);
        return true;
    }

    function forget(network) {
        if (!network)
            return false;
        if (!root.runAction("forget", network))
            return false;
        network.forget();
        return true;
    }

    readonly property string _enterpriseScript:
        "command -v nmcli >/dev/null 2>&1 || exit 127;" +
        "u=$(uuidgen); IFS= read -r pw;" +
        " nmcli connection add type wifi con-name \"$1\" ssid \"$1\" connection.uuid \"$u\"" +
        " wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2" +
        " 802-1x.identity \"$2\" 802-1x.auth-timeout 8 >/dev/null" +
        " && printf 'set 802-1x.password %s\\nsave\\nquit\\n' \"$pw\" | nmcli connection edit uuid \"$u\" >/dev/null" +
        " && nmcli connection up uuid \"$u\"" +
        " || { nmcli connection delete uuid \"$u\" >/dev/null 2>&1; false; }"

    function connectEnterprise(network, identity, password) {
        if (!root.runAction("connect", network))
            return false;
        root._secretSupplied = true;
        enterpriseProc.targetSsid = network.name || "";
        enterpriseProc.secret = password;
        enterpriseProc.command = ["bash", "-c", root._enterpriseScript, "nmcli-eap", network.name || "", identity];
        enterpriseProc.running = true;
        return true;
    }

    // Safety net (omarchy's actionTimeout, Panel.qml:1025-1041 there): if
    // the completion signals never fire, this clears a stuck busy row to an
    // honest "Timed out" instead of "Connecting" forever.
    Timer {
        id: actionTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            if (root.actionKind === "")
                return;
            root.failureSsid = root.actionSsid;
            root.failureText = "Timed out";
            root.failureReason = -1;
            root.actionSsid = "";
            root.actionKind = "";
        }
    }

    // The secret is written to stdin the instant the process starts and
    // dropped from JS memory immediately after: never argv, never logged,
    // never lingering.
    Process {
        id: enterpriseProc
        property string secret: ""
        property string targetSsid: ""
        stdinEnabled: true

        onStarted: {
            enterpriseProc.write(enterpriseProc.secret + "\n");
            enterpriseProc.secret = "";
        }

        onExited: function (exitCode) {
            if (root.actionKind !== "connect" || root.actionSsid !== enterpriseProc.targetSsid)
                return;
            actionTimeout.stop();
            if (exitCode === 0) {
                root.clearAction();
                return;
            }
            root.actionSsid = "";
            root.actionKind = "";
            root.failureSsid = enterpriseProc.targetSsid;
            root.failureText = exitCode === 127 ? "nmcli is not installed" : NetworkModel.failureText(NetworkModel.ConnectionFailReason.Unknown);
            root.failureReason = NetworkModel.ConnectionFailReason.Unknown;
        }
    }

    Instantiator {
        model: root.networks
        delegate: Connections {
            id: link
            required property var modelData
            target: link.modelData

            function onConnectionFailed(reason) {
                root.failAction(link.modelData, reason);
            }
            function onConnectedChanged() {
                root.checkActionCompletion(link.modelData);
            }
            function onKnownChanged() {
                root.checkActionCompletion(link.modelData);
            }
            function onStateChangingChanged() {
                root.checkActionCompletion(link.modelData);
            }
        }
    }

    // ---- Launcher password step -----------------------------------------

    // The menu's prompts answer through shell.qml's selectionResolved
    // Connections, the same path LightsService takes.
    readonly property string passwordToken: "wifi-password"
    readonly property string identityToken: "wifi-identity"

    property string pendingSsid: ""
    property string _pendingIdentity: ""

    // Stores the network the prompt is for and returns the first prompt to
    // open: the identity for an enterprise network, else the password.
    function requestSecret(ssid) {
        var network = root.findNetwork(ssid);
        root.pendingSsid = ssid;
        root._pendingIdentity = "";
        var enterprise = !!network && NetworkModel.isEnterprise(network.security);
        return {
            token: enterprise ? root.identityToken : root.passwordToken,
            prompt: (enterprise ? "Identity for " : "Password for ") + ssid
        };
    }

    // "" when the token is not ours or the step ended without a connect,
    // "identity" when the password prompt is next, "submitted" once a
    // connect has started.
    function resolveInput(token, value, cancelled) {
        if (token !== root.identityToken && token !== root.passwordToken)
            return "";
        var ssid = root.pendingSsid;
        if (cancelled || ssid === "" || value === null || value.length === 0) {
            root._clearPending();
            return "";
        }
        if (token === root.identityToken) {
            root._pendingIdentity = value;
            return "identity";
        }
        var network = root.findNetwork(ssid);
        var identity = root._pendingIdentity;
        root._clearPending();
        if (!network)
            return "";
        var started = identity !== "" && NetworkModel.isEnterprise(network.security)
            ? root.connectEnterprise(network, identity, value)
            : root.connectPsk(network, value);
        return started ? "submitted" : "";
    }

    function _clearPending() {
        root.pendingSsid = "";
        root._pendingIdentity = "";
    }
}

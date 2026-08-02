.pragma library

// Pure model for the network panel's wifi rows (M14 Task 1): sort order,
// section membership, security classification, and the signal-bar glyph.
// No Quickshell access, so it's testable head-on (mirrors workspaces.js).
// Reimplemented from omarchy's Model.js sortWifiRows/networkFailureReason
// (~/Developer/omarchy/shell/plugins/panels/network/Model.js) against
// Quickshell.Networking's native WifiNetwork properties (connected/known/
// signalStrength/security) instead of iwctl output, so signalStrength here
// stays the toolkit's native 0..1 fraction rather than omarchy's 0..100.
//
// WifiSecurityType and ConnectionFailReason are mirrored as plain ints
// (verified against the pinned quickshell source, never guessed) because a
// .pragma library file can't import Quickshell.Networking's QML enums.
// Callers that already have the real enum (Task 2's panel) can pass its
// values straight through — they compare equal to these.

// src/network/enums.hpp:107-128
var WifiSecurityType = {
    Wpa3SuiteB192: 0,
    Sae: 1,
    Wpa2Eap: 2,
    Wpa2Psk: 3,
    WpaEap: 4,
    WpaPsk: 5,
    StaticWep: 6,
    DynamicWep: 7,
    Leap: 8,
    Owe: 9,
    Open: 10,
    Unknown: 11
};

// src/network/enums.hpp:67-84
var ConnectionFailReason = {
    Unknown: 0,
    NoSecrets: 1,
    WifiClientDisconnected: 2,
    WifiClientFailed: 3,
    WifiAuthTimeout: 4,
    WifiNetworkLost: 5
};

// Open and Owe are the two unauthenticated types; everything else needs a
// secret of some kind (enums.hpp:107-128).
function isSecured(security) {
    return security !== WifiSecurityType.Open && security !== WifiSecurityType.Owe;
}

// 802.1x/EAP networks need an identity + nmcli side-script, not a plain
// PSK — Task 2 renders these as a dim ENTERPRISE tag instead of a prompt.
function isEnterprise(security) {
    return security === WifiSecurityType.WpaEap || security === WifiSecurityType.Wpa2Eap;
}

// Connected first, then known (saved) networks, then everything else —
// each tier sorted by signal strength descending. Non-mutating.
function sortWifiRows(rows) {
    var list = Array.isArray(rows) ? rows.slice() : [];
    list.sort(function (a, b) {
        if (a.connected !== b.connected) return a.connected ? -1 : 1;
        if (a.known !== b.known) return a.known ? -1 : 1;
        return (b.signalStrength || 0) - (a.signalStrength || 0);
    });
    return list;
}

// Section header a row falls under once sortWifiRows has grouped connected
// in with known — the connected row is always known (you can't be
// connected to a network with no saved settings), so this only ever needs
// to look at `known` itself.
function sectionOf(row) {
    return row.known ? "KNOWN" : "AVAILABLE";
}

// Uppercase status line for a connectionFailed(reason) signal.
function failureText(reason) {
    if (reason === ConnectionFailReason.NoSecrets) return "PASSPHRASE REQUIRED";
    if (reason === ConnectionFailReason.WifiAuthTimeout) return "WRONG PASSWORD";
    if (reason === ConnectionFailReason.WifiNetworkLost) return "NETWORK LOST";
    return "CONNECTION FAILED";
}

// strength is a 0..1 fraction (src/network/wifi.hpp:22), not 0..100 — see
// CLAUDE.md's percentage/fraction rule. Five-cell block/light-shade bar,
// moved out of NetworkPanel.qml unchanged.
function signalBar(strength) {
    var segments = 5;
    var filled = Math.round(Math.max(0, Math.min(1, strength)) * segments);
    var bar = "";
    for (var i = 0; i < segments; i++)
        bar += (i < filled) ? "█" : "░";
    return bar;
}

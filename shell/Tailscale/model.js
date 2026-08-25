.pragma library

// Pure model for the Tailscale panel/widget (M16 Task 8): parses `tailscale
// status --json` output into the shape TailscalePanel.qml renders directly.
// No Quickshell access, so it's testable head-on (mirrors bluetooth/model.js,
// network/model.js). Field names verified against a real `tailscale status
// --json` run (BackendState, Self.HostName, Self.TailscaleIPs,
// Peer.<nodekey>.{HostName, TailscaleIPs, Online, OS}), not the omarchy
// panel's own richer parse (~/Developer/omarchy/shell/plugins/panels/
// tailscale/Model.js), reimplemented narrower for what this shell's panel
// actually shows: no exit nodes, no Mullvad, no multi-account switching.

function _firstIp(ips) {
    return (Array.isArray(ips) && ips.length > 0 && typeof ips[0] === "string") ? ips[0] : null;
}

// Falls back to the peer's own map key (its stable nodekey) when the daemon
// hasn't reported a HostName yet, never a blank row.
function _peer(id, raw) {
    var p = raw || {};
    return {
        name: (typeof p.HostName === "string" && p.HostName !== "") ? p.HostName : id,
        online: p.Online === true,
        ip: _firstIp(p.TailscaleIPs),
        os: (typeof p.OS === "string" && p.OS !== "") ? p.OS : null
    };
}

// Online-first, then alphabetical within each group, matches the ledger
// sort every other panel table uses (NetworkPanel's connected-first,
// BluetoothPanel's connected/paired/available buckets).
function _sortPeers(peers) {
    return peers.slice().sort(function (a, b) {
        if (a.online !== b.online) return a.online ? -1 : 1;
        return a.name.localeCompare(b.name);
    });
}

// `raw` is `tailscale status --json`'s stdout, verbatim. Honest null/[]
// for anything missing or unparsable, never a thrown exception, a
// daemon-unreachable run prints a plain-text error instead of JSON, and an
// unparsable response is exactly as unusable to the caller as a process
// failure (TailscalePanel.qml folds both into its "NO TAILSCALE" state).
function parseStatus(raw) {
    var text = String(raw || "").trim();
    var empty = { ok: false, backendState: null, running: false, needsLogin: false, selfName: null, selfIps: [], peers: [] };
    if (text === "")
        return empty;

    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return empty;
    }
    if (!data || typeof data !== "object")
        return empty;

    var backendState = (typeof data.BackendState === "string") ? data.BackendState : null;
    var self = data.Self || {};
    var selfName = (typeof self.HostName === "string" && self.HostName !== "") ? self.HostName : null;
    var selfIps = Array.isArray(self.TailscaleIPs) ? self.TailscaleIPs.filter(function (ip) { return typeof ip === "string"; }) : [];

    var peers = [];
    var rawPeers = data.Peer || {};
    for (var id in rawPeers)
        peers.push(_peer(id, rawPeers[id]));

    return {
        ok: true,
        backendState: backendState,
        running: backendState === "Running",
        needsLogin: backendState === "NeedsLogin",
        selfName: selfName,
        selfIps: selfIps,
        peers: _sortPeers(peers)
    };
}

// First address from a parsed status's own Self entry, or null, kept as
// its own function (rather than inlined at every call site) per the two
// functions this file is scoped to.
function selfIp(status) {
    return (status && Array.isArray(status.selfIps)) ? _firstIp(status.selfIps) : null;
}

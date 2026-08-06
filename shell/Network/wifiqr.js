.pragma library

// Pure payload + matrix logic for the network panel's Wi-Fi QR share
// (omarchy's `bin/omarchy-network-qr` reimplemented as testable JS: its
// escaping rules, its security-branch choice, and its ASCII-pair collapse —
// nothing else). NetworkPanel.qml drives the real `nmcli`/`qrencode`
// Processes and feeds their stdout through these helpers; nothing here
// touches Qt.
//
// Constraints: the passphrase passes through `buildPayload`. It stays an
// argument and a return value — this file never logs it, never keeps it in
// a module-level variable, and never writes it anywhere. The caller holds
// the returned payload only long enough to write it to qrencode's stdin
// (never argv, which /proc publishes to every local user).

// The WIFI: URI reserves four characters. Backslash must be doubled first,
// or the escapes added below would themselves be re-escaped.
function escapeValue(value) {
    return String(value === undefined || value === null ? "" : value)
        .replace(/\\/g, "\\\\")
        .replace(/;/g, "\\;")
        .replace(/,/g, "\\,")
        .replace(/:/g, "\\:");
}

// 802.1x networks authenticate against a server, not a shared secret;
// there is nothing to put in the payload's P: field at all, so the caller
// renders an honest refusal rather than a QR that cannot work. Both spellings
// NetworkManager uses for key-mgmt appear here ("wpa-eap", "ieee8021x").
function isEnterpriseKeyMgmt(keyMgmt) {
    var k = String(keyMgmt || "").toLowerCase();
    return k.indexOf("eap") >= 0 || k.indexOf("ieee8021x") >= 0;
}

// The five `nmcli --get-values` lines, in the order NetworkPanel.qml
// requests them: ssid, key-mgmt, psk, hidden, wep-key0. nmcli prints one
// line per requested field — an empty line when the property is unset — so
// a short read means the command answered for fewer fields than were asked
// for, and the missing ones stay empty rather than shifting position.
function parseFields(text) {
    var lines = String(text === undefined || text === null ? "" : text).split("\n");
    function at(i) {
        return lines[i] !== undefined ? lines[i] : "";
    }
    return {
        ssid: at(0),
        keyMgmt: at(1),
        password: at(2),
        hidden: at(3),
        wepKey: at(4)
    };
}

// Fields -> { ok: true, payload } or { ok: false, error }, where error is
// one of "no_ssid" / "enterprise" / "no_password". Error codes, not display
// strings: NetworkPanel.qml owns the uppercase honest-state text, the same
// split usage.js/UsagePanel.qml already use.
function buildPayload(fields) {
    var f = fields || {};
    var ssid = String(f.ssid || "");
    if (ssid === "")
        return { ok: false, error: "no_ssid" };
    if (isEnterpriseKeyMgmt(f.keyMgmt))
        return { ok: false, error: "enterprise" };

    var keyMgmt = String(f.keyMgmt || "");
    var wepKey = String(f.wepKey || "");
    var security;
    var password;
    if (keyMgmt !== "" && keyMgmt !== "none") {
        password = String(f.password || "");
        if (password === "")
            return { ok: false, error: "no_password" };
        security = "WPA";
    } else if (wepKey !== "") {
        // NetworkManager models WEP as key-mgmt "none" plus a wep-key, so
        // an absent key-mgmt alone does not mean open: encoding this as
        // nopass would produce a QR that silently fails to join.
        password = wepKey;
        security = "WEP";
    } else {
        // An open network carries no secret, so P: stays empty rather than
        // echoing whatever the psk field happened to hold.
        password = "";
        security = "nopass";
    }

    var payload = "WIFI:T:" + security + ";S:" + escapeValue(ssid) + ";P:" + escapeValue(password) + ";";
    if (String(f.hidden || "").toLowerCase() === "yes")
        payload += "H:true;";
    return { ok: true, payload: payload + ";" };
}

// `qrencode --type ASCII` writes every module as TWO characters ("##" dark,
// "  " light) so the code stays square in a terminal's 2:1 character cell.
// Collapse each pair back to one "0"/"1" and hand back an array of row
// strings the caller can render as real square rectangles.
//
// A QR symbol is square and --margin applies the quiet zone on all four
// sides, so the collapsed matrix must have as many columns as rows.
// Anything else — empty stdout, a truncated read, an all-space quiet-zone
// row trimmed away by something in the pipe — returns an empty matrix, so
// the caller shows an honest error instead of a partial or padded code.
function parseMatrix(ascii) {
    var lines = String(ascii === undefined || ascii === null ? "" : ascii).split("\n");
    while (lines.length > 0 && lines[lines.length - 1] === "")
        lines.pop();
    if (lines.length === 0)
        return [];

    var rows = [];
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line.length % 2 !== 0)
            return [];
        var row = "";
        for (var c = 0; c < line.length; c += 2)
            row += (line.charAt(c) === "#" || line.charAt(c + 1) === "#") ? "1" : "0";
        if (row.length !== lines.length)
            return [];
        rows.push(row);
    }
    return rows;
}

.pragma library

// Location's own lookups for a machine geoclue cannot place. geoclue's wifi
// source only reads wpa_supplicant, so under iwd (NetworkManager's
// wifi.backend = "iwd") it never has a BSSID to send and never gets a fix.
// LocationService then sends beaconDB the same query itself, with the
// BSSIDs iwd publishes on the system bus (or nmcli's, under
// wpa_supplicant), and beaconDB answers from its IP database when it knows
// none of them. No Process or network in here.

function _str(value) {
    return value === undefined || value === null ? "" : String(value);
}

var GEOLOCATE_URL = "https://api.beacondb.net/v1/geolocate";

// `busctl --json=short call net.connman.iwd / ...ObjectManager
// GetManagedObjects`: every BasicServiceSet's Address, minus the ones under
// a network whose name opts out of location services (`_nomap`).
function accessPointsFromIwd(text) {
    var objects;
    try {
        objects = JSON.parse(text).data[0];
    } catch (e) {
        return [];
    }
    if (!objects || typeof objects !== "object")
        return [];
    var result = [];
    Object.keys(objects).forEach(function (path) {
        var bss = objects[path]["net.connman.iwd.BasicServiceSet"];
        if (!bss || !bss.Address)
            return;
        var parent = objects[path.slice(0, path.lastIndexOf("/"))] || {};
        var network = parent["net.connman.iwd.Network"] || {};
        var name = network.Name ? _str(network.Name.data) : "";
        if (/_nomap$/.test(name))
            return;
        result.push({ macAddress: _str(bss.Address.data).toLowerCase() });
    });
    return result;
}

function _terseFields(line) {
    var fields = [""];
    for (var i = 0; i < line.length; i++) {
        var c = line[i];
        if (c === "\\" && i + 1 < line.length) {
            fields[fields.length - 1] += line[++i];
        } else if (c === ":") {
            fields.push("");
        } else {
            fields[fields.length - 1] += c;
        }
    }
    return fields;
}

// `nmcli -t -f BSSID,SSID,SIGNAL,FREQ dev wifi list`: terse mode escapes
// the colons inside a field with a backslash.
function accessPointsFromNmcli(text) {
    var result = [];
    _str(text).split("\n").forEach(function (line) {
        var fields = _terseFields(line);
        if (fields.length < 4 || !/^[0-9A-Fa-f:]{17}$/.test(fields[0]) || /_nomap$/.test(fields[1]))
            return;
        var signal = parseInt(fields[2], 10);
        var ap = { macAddress: fields[0].toLowerCase() };
        if (isFinite(signal))
            ap.signalStrength = Math.round(signal / 2 - 100);
        var freq = parseInt(fields[3], 10);
        if (isFinite(freq))
            ap.frequency = freq;
        result.push(ap);
    });
    return result;
}

// The scan script prints which backend answered on its first line.
function accessPointsFromScan(text) {
    var body = _str(text);
    var nl = body.indexOf("\n");
    var head = nl === -1 ? body : body.slice(0, nl);
    var rest = nl === -1 ? "" : body.slice(nl + 1);
    if (head === "iwd")
        return accessPointsFromIwd(rest);
    if (head === "nm")
        return accessPointsFromNmcli(rest);
    return [];
}

function geolocateBody(accessPoints) {
    return JSON.stringify({ considerIp: true, wifiAccessPoints: accessPoints || [] });
}

// {latitude, longitude, accuracy, source} with source "wifi" or "ip"
// (beaconDB marks its IP answer `fallback: "ipf"`), null for anything else.
function parseGeolocate(body) {
    var data;
    try {
        data = JSON.parse(body);
    } catch (e) {
        return null;
    }
    var loc = data && data.location;
    if (!loc || !isFinite(Number(loc.lat)) || !isFinite(Number(loc.lng)))
        return null;
    return {
        latitude: Number(loc.lat),
        longitude: Number(loc.lng),
        accuracy: Number(data.accuracy) || 0,
        source: data.fallback === "ipf" ? "ip" : "wifi"
    };
}

// Rounded to about a kilometre, so a fix that drifts a few metres is the
// same place and never another lookup.
function placeKey(latitude, longitude) {
    if (!isFinite(latitude) || !isFinite(longitude))
        return "";
    return latitude.toFixed(2) + "," + longitude.toFixed(2);
}

function reverseUrl(key) {
    var parts = key.split(",");
    return "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&accept-language=en&lat="
        + parts[0] + "&lon=" + parts[1];
}

// "Teguise, Canary Islands": the town and its region, "" when Nominatim
// has neither.
function parsePlace(body) {
    var data;
    try {
        data = JSON.parse(body);
    } catch (e) {
        return "";
    }
    var a = (data && data.address) || {};
    var town = _str(a.city || a.town || a.village || a.municipality || a.county || data.name);
    var region = _str(a.state || a.country);
    if (town !== "" && region !== "" && town !== region)
        return town + ", " + region;
    return town !== "" ? town : region;
}

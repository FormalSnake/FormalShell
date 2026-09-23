.pragma library

// Pure model groundwork for the MPRIS surfaces: which registered player the
// shell speaks to, the loop-state naming and cycle order, and the two value
// clamps. No Quickshell.Services.Mpris access, so it's testable head-on
// (mirrors Audio/model.js).

// Rows are plain objects the caller builds by reading the live MprisPlayer
// properties in QML, never MprisPlayer instances themselves. The binding
// that builds them is where the property capture has to happen.

// An explicit pick wins for as long as that source is still there;
// otherwise an actually-playing one, otherwise the first. A pick whose source
// has gone falls back rather than pinning the panel to a name nothing answers
// on any more. Rows carrying `auto: false` (an app with audio and no MPRIS)
// are only ever picked by hand: auto never lands on a source the transport
// cannot drive.
function pickPlayerId(rows, selectedId) {
    if (!rows || rows.length === 0) return "";
    if (selectedId) {
        for (var i = 0; i < rows.length; i++)
            if (rows[i].id === selectedId) return selectedId;
    }
    var first = "";
    for (var j = 0; j < rows.length; j++) {
        if (rows[j].auto === false) continue;
        if (rows[j].isPlaying) return rows[j].id;
        if (!first) first = rows[j].id;
    }
    return first;
}

// What a player row can be recognised by on a Pipewire stream: the bus name's
// first word (org.mpris.MediaPlayer2.firefox.instance_1_2 -> firefox) and the
// identity it publishes, lowercased.
function playerTokens(row) {
    var out = [];
    var bus = busSuffix(row.id).split(/[.]/)[0].toLowerCase();
    if (bus.length >= 3) out.push(bus);
    var identity = String(row.identity || "").toLowerCase();
    if (identity.length >= 3 && out.indexOf(identity) < 0) out.push(identity);
    return out;
}

// Which player row a playback stream belongs to, or "". `keys` are the
// stream's application.name, application.process.binary, application.id and
// node.name. A key and a token match when one holds the other ("google
// chrome" and "chrome", "mozilla firefox" and "firefox"). MPRIS carries no
// pid, so a name is all there is to go on.
function streamOwner(keys, rows) {
    var names = [];
    for (var k = 0; k < (keys || []).length; k++) {
        var key = String(keys[k] || "").toLowerCase();
        if (key.length >= 3) names.push(key);
    }
    for (var i = 0; i < (rows || []).length; i++) {
        var tokens = playerTokens(rows[i]);
        for (var t = 0; t < tokens.length; t++)
            for (var n = 0; n < names.length; n++)
                if (names[n].indexOf(tokens[t]) >= 0 || tokens[t].indexOf(names[n]) >= 0)
                    return rows[i].id;
    }
    return "";
}

// The sink-input index `pactl move-sink-input` takes for a Pipewire node, out
// of `pactl -f json list sink-inputs`, or -1.
function sinkInputIndex(text, nodeId) {
    var rows;
    try {
        rows = JSON.parse(text);
    } catch (e) {
        return -1;
    }
    if (!Array.isArray(rows)) return -1;
    for (var i = 0; i < rows.length; i++) {
        var props = rows[i] && rows[i].properties;
        if (props && String(props["object.id"]) === String(nodeId) && typeof rows[i].index === "number")
            return rows[i].index;
    }
    return -1;
}

var BUS_PREFIX = "org.mpris.MediaPlayer2.";

// What is left of a bus name once the well-known prefix is off it:
// org.mpris.MediaPlayer2.mpv -> mpv, and the second instance of one app ->
// mpv.instance-<something>, which is the only thing telling two of them apart.
function busSuffix(id) {
    var name = String(id || "");
    if (name.indexOf(BUS_PREFIX) === 0)
        return name.substring(BUS_PREFIX.length);
    var dot = name.lastIndexOf(".");
    return dot >= 0 ? name.substring(dot + 1) : name;
}

// `identity` is the human name a player publishes for itself; a player that
// publishes none falls back to its bus name rather than an empty cell.
function playerLabel(row) {
    if (!row) return "";
    return row.identity ? row.identity : busSuffix(row.id);
}

// Two windows of one app publish the same identity ("mpv", "mpv"), which is a
// switcher listing the same row twice as far as anyone reading it can tell.
// Rows whose label collides fall back to the bus name, which is unique by
// construction; rows with a label of their own keep it.
function withLabels(rows) {
    if (!rows) return [];
    var counts = {};
    var i, label;
    for (i = 0; i < rows.length; i++) {
        label = playerLabel(rows[i]);
        counts[label] = (counts[label] || 0) + 1;
    }
    var out = [];
    for (i = 0; i < rows.length; i++) {
        label = playerLabel(rows[i]);
        out.push({
            id: rows[i].id,
            kind: rows[i].kind || "mpris",
            auto: rows[i].auto !== false,
            identity: rows[i].identity,
            label: counts[label] > 1 ? busSuffix(rows[i].id) : label,
            isPlaying: rows[i].isPlaying === true
        });
    }
    return out;
}

// MPRIS LoopStatus is None/Track/Playlist on the wire and
// MprisLoopState.None/Track/Playlist in quickshell; these lowercase names are
// what the IPC contract and the panel speak, so only MediaService has to know
// the enum.
var LOOP_NAMES = ["none", "track", "playlist"];

function isLoopName(name) {
    return LOOP_NAMES.indexOf(String(name)) !== -1;
}

// Off -> repeat the queue -> repeat this track -> off, the order every
// player's own repeat button walks.
function nextLoop(name) {
    if (name === "none") return "playlist";
    if (name === "playlist") return "track";
    return "none";
}

// MPRIS Volume is a double where 1.0 is the player's own full scale. Values
// above it are legal on the wire (overdrive) but the panel's flat track never
// draws past full, same rule Audio/model.js's clampDevice follows.
function clampVolume(v) {
    var n = Number(v);
    if (!isFinite(n)) return 0;
    return Math.max(0, Math.min(1, n));
}

// Seek fraction of the track, clamped to the track.
function clampFraction(v) {
    var n = Number(v);
    if (!isFinite(n)) return 0;
    return Math.max(0, Math.min(1, n));
}

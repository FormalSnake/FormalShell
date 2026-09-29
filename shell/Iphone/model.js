.pragma library

// Portions from omarchy-iphone (MIT, Copyright (c) 2026 kbbahaPro)

// Pure model for the iPhone mirror (M75 Task 2, plan at
// docs/superpowers/plans/2026-09-28-m75-iphone.md). No Quickshell access, so
// tst_iphone_model.qml drives it head-on with the bridge's own JSONL.
//
// The wire is `omarchy-iphone-bridge listen` (omarchy-iphone @ 586f37d,
// bin/omarchy-iphone-bridge): one JSON object per stdout line, `type` one of
// history, notification, dismiss, status, pairingCode, advertising, forgot,
// error, hci. nix/iphone-bridge-bond.patch adds `paired`/`address` to status
// and the `forgot` event. A notification's `id` is ancs4linux's
// per-connection id (the ANCS uid offset by a random base chosen per
// connection), so it only means anything inside the `session` it arrived in.

var CATEGORY = {
    Other: 0,
    IncomingCall: 1,
    MissedCall: 2,
    Voicemail: 3,
    Social: 4
};

var _CATEGORY_LABEL = {
    1: "Incoming call",
    2: "Missed call",
    3: "Voicemail",
    4: "Social",
    5: "Schedule",
    6: "Email",
    7: "News",
    8: "Health",
    9: "Finance",
    10: "Location",
    11: "Entertainment"
};

var DEFAULT_DEDUPE = [
    { phone: "com.apple.MobileSMS", local: ["Messages", "es.canarycoders.messages"], window: 30 }
];
var DEFAULT_FOCUS_WINDOW = 900;
var FOCUS_MODES = ["respect", "hide", "ignore"];

function _str(value) {
    return value === undefined || value === null ? "" : String(value);
}

function _int(value) {
    var n = Number(value);
    return isFinite(n) ? Math.round(n) : 0;
}

function categoryLabel(category) {
    return _CATEGORY_LABEL[_int(category)] || "";
}

// The bridge's notification object, every field defaulted, so nothing past
// here guards against `undefined`. `positiveAction`/`negativeAction` are the
// phone's own labels ("Clear", "Answer", "Decline"), "" when the phone
// offers no such action.
function _notification(raw) {
    return {
        id: _int(raw.id),
        bundleId: _str(raw.appId),
        appName: _str(raw.appName) || _str(raw.appId) || "iPhone",
        title: _str(raw.title),
        subtitle: _str(raw.subtitle),
        body: _str(raw.body),
        deviceName: _str(raw.deviceName),
        deviceHandle: _str(raw.deviceHandle),
        positiveAction: _str(raw.positiveAction),
        negativeAction: _str(raw.negativeAction),
        category: _int(raw.category),
        categoryCount: _int(raw.categoryCount),
        silent: raw.silent === true,
        important: raw.important === true,
        preexisting: raw.preexisting === true,
        session: _int(raw.session),
        ts: Number(raw.ts) > 0 ? Number(raw.ts) : 0
    };
}

// One stdout line to one event, or null for a blank line, bad JSON or a type
// this shell does not act on.
function parseEvent(line) {
    var text = _str(line).trim();
    if (text === "")
        return null;
    var raw;
    try {
        raw = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!raw || typeof raw !== "object")
        return null;

    switch (raw.type) {
    case "notification":
        var n = _notification(raw);
        n.type = "notification";
        return n;
    case "history":
        return {
            type: "history",
            items: (Array.isArray(raw.items) ? raw.items : [])
                .filter(function (item) { return item && typeof item === "object"; })
                .map(_notification)
        };
    case "dismiss":
        return { type: "dismiss", id: _int(raw.id) };
    case "status":
        // `installed` is left out on purpose: the bridge answers it by
        // looking for ancs4linux-observer under /usr/bin and /usr/local/bin,
        // which is false on every NixOS host. `observer` (the daemon owning
        // its bus name) is the honest signal.
        var battery = Number(raw.battery);
        return {
            type: "status",
            observer: raw.observer === true,
            connected: raw.connected === true,
            paired: raw.paired === true,
            address: _str(raw.address).toUpperCase(),
            deviceName: _str(raw.deviceName),
            battery: isFinite(battery) && battery >= 0 ? Math.min(100, battery) : -1
        };
    case "pairingCode":
        return { type: "pairingCode", code: _str(raw.code) };
    case "advertising":
        return { type: "advertising", hci: _str(raw.hci), name: _str(raw.name) };
    case "forgot":
        return { type: "forgot", address: _str(raw.address).toUpperCase() };
    case "error":
        return { type: "error", message: explainError(raw.message) };
    }
    return null;
}

// BlueZ's errors reach the bridges as GLib's own rendering, e.g.
// "subscribe: g-io-error-quark: GDBus.Error:org.bluez.Error.Failed: Not
// connected (36)". The two BlueZ states a person can act on get a sentence;
// anything else keeps its step and BlueZ's message without the D-Bus wrapping.
function explainError(message) {
    var text = _str(message).trim();
    if (text === "")
        return "Unknown error";
    if (/\bNot connected\b/i.test(text))
        return "The iPhone is not connected over Bluetooth LE";
    if (/org\.bluez\.Error\.(AuthenticationFailed|AuthenticationRejected|NotPermitted)\b/.test(text))
        return "The iPhone refused this laptop's keys. Pair again";
    return text.replace(/g-io-error-quark: /g, "").replace(/GDBus\.Error:[\w.]+: /g, "");
}

// Whether `pair` has to drop BlueZ's bond first: BlueZ holds one for the
// phone but it is not connected, which is what a phone that forgot this
// laptop looks like from here. A connected phone keeps its bond.
function forgetBeforePair(status) {
    return !!status && status.paired === true && status.connected !== true && _str(status.address) !== "";
}

// Newest first, one row per id, capped. ANCS resends an id when the phone
// modifies a notification, which replaces the row rather than adding one.
function upsert(items, entry, limit) {
    var next = [entry].concat(items.filter(function (e) { return e.id !== entry.id; }));
    return next.length > limit ? next.slice(0, limit) : next;
}

function removeById(items, id) {
    var next = items.filter(function (e) { return e.id !== id; });
    return next.length === items.length ? items : next;
}

// What iOS's Focus asked for this notification, under `mode`: "toast", a
// normal arrival; "quiet", the centre's history with no toast and no sound;
// "drop", not mirrored. `silent` is the only signal there is (ANCS's
// EventFlagSilent, set on everything a Focus holds back).
function focusVerdict(entry, mode) {
    if (!entry || entry.silent !== true)
        return "toast";
    if (mode === "ignore")
        return "toast";
    if (mode === "hide")
        return "drop";
    return "quiet";
}

// focusVerdict plus the gates in front of it. A replayed notification
// (`preexisting`, the phone's backlog on every reconnect) stays in the
// recent list only: it already happened, and a reconnect would otherwise
// refill the centre with everything still on the lock screen.
function route(entry, cfg) {
    cfg = cfg || {};
    if (cfg.enable === false)
        return "drop";
    if (isBlocked(entry, cfg.block))
        return "drop";
    if (entry.preexisting === true)
        return "drop";
    return focusVerdict(entry, cfg.focus);
}

function isBlocked(entry, block) {
    var list = Array.isArray(block) ? block : [];
    var id = _str(entry && entry.bundleId).toLowerCase();
    return id !== "" && list.some(function (b) { return _str(b).toLowerCase() === id; });
}

// Bidi isolates and marks iOS wraps contact names in, zero-width joiners and
// the BOM: invisible, and present on one side of a pair and not the other.
var _INVISIBLE_RE = /[​-‏‪-‮⁠-⁩﻿]/g;

function _clean(text) {
    var s = _str(text);
    if (typeof s.normalize === "function")
        s = s.normalize("NFC");
    return s.replace(_INVISIBLE_RE, "")
        .replace(/[‘’]/g, "'")
        .replace(/[“”]/g, "\"")
        .replace(/\s+/g, " ")
        .trim()
        .toLowerCase();
}

// The comparison key for one sender and one message.
function normalise(title, body) {
    return _clean(title) + "\u0000" + _clean(body);
}

// Every (sender, body) reading a notification supports. The two clients do
// not put the sender in the same place: es.canarycoders.messages sends the
// chat title as the summary and, in a group, "Sender: text" as the body
// (crates/core/src/notify.rs), while ANCS carries the sender in `title` or
// `subtitle`. A pair matches when any reading of one equals any reading of
// the other.
var _SENDER_PREFIX_RE = /^([^:\n]{1,64}):\s+([\s\S]+)$/;

function _readings(sender, subtitle, body) {
    var keys = [normalise(sender, body)];
    if (_str(subtitle).trim() !== "")
        keys.push(normalise(subtitle, body));
    var m = _str(body).match(_SENDER_PREFIX_RE);
    if (m)
        keys.push(normalise(m[1], m[2]));
    return keys;
}

function _overlap(a, b) {
    return a.some(function (k) { return b.indexOf(k) >= 0; });
}

// settings.json's list, anything malformed dropped rather than guessed at.
function dedupeRules(raw) {
    if (!Array.isArray(raw))
        return [];
    return raw.filter(function (r) {
        return r && typeof r === "object" && _str(r.phone) !== "" && Array.isArray(r.local);
    }).map(function (r) {
        var window = Number(r.window);
        return {
            phone: _str(r.phone).toLowerCase(),
            local: r.local.map(function (l) { return _str(l).toLowerCase(); })
                .filter(function (l) { return l !== ""; }),
            windowMs: (isFinite(window) && window > 0 ? window : 30) * 1000
        };
    });
}

function _ruleFor(rules, bundleId) {
    var id = _str(bundleId).toLowerCase();
    for (var i = 0; i < rules.length; i++) {
        if (rules[i].phone === id)
            return rules[i];
    }
    return null;
}

function _isLocalFor(rule, entry) {
    if (!entry || entry.source === "iphone" || entry.local === true)
        return false;
    var name = _str(entry.appName).toLowerCase();
    var desktop = _str(entry.desktopEntry).toLowerCase();
    return rule.local.some(function (l) { return l === name || (desktop !== "" && l === desktop); });
}

function _within(rule, entry, now) {
    return Math.abs(now - Number(entry.arrivedAt || 0)) <= rule.windowMs;
}

// A phone arrival against the notification centre's entries: the local
// entry it duplicates, or null. The local one wins, so a non-null answer
// means the phone arrival is dropped. `rules` is dedupeRules()'s output.
function dedupe(rules, phoneEntry, localEntries, now) {
    var rule = _ruleFor(rules, phoneEntry.bundleId);
    if (!rule)
        return null;
    var phoneKeys = _readings(phoneEntry.title, phoneEntry.subtitle, phoneEntry.body);
    var list = localEntries || [];
    for (var i = 0; i < list.length; i++) {
        var local = list[i];
        if (!_isLocalFor(rule, local) || !_within(rule, local, now))
            continue;
        if (_overlap(phoneKeys, _readings(local.summary, "", local.body)))
            return local;
    }
    return null;
}

// The other direction: a local arrival against the centre's phone entries
// (`source: "iphone"`, the bridge's fields under `phone`). Answers the ids
// of the phone entries it supersedes, which the caller removes.
function superseded(rules, localEntry, entries, now) {
    var localKeys = _readings(localEntry.summary, "", localEntry.body);
    var ids = [];
    (entries || []).forEach(function (entry) {
        if (entry.source !== "iphone" || !entry.phone)
            return;
        var rule = _ruleFor(rules, entry.phone.bundleId);
        if (!rule || !_isLocalFor(rule, localEntry) || !_within(rule, entry, now))
            return;
        if (_overlap(localKeys, _readings(entry.phone.title, entry.phone.subtitle, entry.phone.body)))
            ids.push(entry.id);
    });
    return ids;
}

// The Focus heuristic. No accessory can read the phone's Focus state, so
// "in Focus" means the newest live arrival inside the last `windowSec` was
// silent: a silent one in the window and no audible one since. `arrivals`
// is [{ at: ms, silent: bool }] in any order.
function inFocus(arrivals, now, windowSec) {
    var windowMs = (Number(windowSec) > 0 ? Number(windowSec) : DEFAULT_FOCUS_WINDOW) * 1000;
    var newest = null;
    (arrivals || []).forEach(function (a) {
        if (now - a.at > windowMs || a.at > now)
            return;
        if (newest === null || a.at >= newest.at)
            newest = a;
    });
    return newest !== null && newest.silent === true;
}

// iphone.notifications.syncDnd, one step. `prev` is { owned, focus } from
// the previous step (start from { owned: false, focus: false }). Answers
// { owned, focus, set } where `set` is true/false to write DND, or null to
// leave it. Only edges act, so a DND the owner clears mid-Focus stays
// cleared; and only a DND this function turned on is ever turned off, so
// one set by hand, before or during Focus, is never touched.
function syncDndStep(prev, focus, dnd, enabled) {
    var active = enabled === true && focus === true;
    var owned = prev.owned === true && dnd === true;
    var set = null;
    if (active && prev.focus !== true && dnd !== true) {
        set = true;
        owned = true;
    } else if (!active && prev.focus === true && owned) {
        set = false;
        owned = false;
    }
    return { owned: owned, focus: active, set: set };
}

// One-time codes. A bare number is not a code: one of the context words
// has to be present, which keeps prices, order numbers and years off the
// clipboard.
var _CODE_CONTEXT = /\b(code|otp|passcode|pass ?code|verification|verify|verifica|2fa|two[- ]factor|one[- ]time|security|auth(entication)?|token|pin)\b/i;
var _CODE_PATTERNS = [
    /\b(\d{3})[- ](\d{3})\b/,
    /\b(\d{4,8})\b/
];

function extractCode(text) {
    var hay = _str(text);
    if (!_CODE_CONTEXT.test(hay))
        return "";
    for (var i = 0; i < _CODE_PATTERNS.length; i++) {
        var m = hay.match(_CODE_PATTERNS[i]);
        if (!m)
            continue;
        var code = m.length > 2 && m[2] !== undefined ? m[1] + m[2] : m[1];
        if (code.length === 4 && /^(19|20)\d\d$/.test(code))
            continue;
        return code;
    }
    return "";
}

// Bundle id to an icon name from shell/Theme/icons.js. A call's category
// outranks the app, since the phone app raises all three kinds.
var _APP_ICONS = {
    "com.apple.mobilesms": "message-circle",
    "com.apple.mobilephone": "phone",
    "com.apple.facetime": "video",
    "com.apple.mobilemail": "mail",
    "com.apple.mobilecal": "calendar",
    "com.apple.reminders": "list-todo",
    "com.apple.music": "music",
    "com.apple.health": "heart-pulse",
    "com.apple.maps": "map",
    "com.apple.news": "newspaper",
    "com.apple.passbook": "wallet",
    "net.whatsapp.whatsapp": "message-circle",
    "org.whispersystems.signal": "message-circle",
    "ph.telegra.telegraph": "send",
    "com.hammerandchisel.discord": "message-square",
    "com.tinyspeck.chatlyio": "hash",
    "com.google.gmail": "mail",
    "com.microsoft.office.outlook": "mail",
    "com.spotify.client": "music"
};

function appIcon(bundleId, category) {
    var c = _int(category);
    if (c === CATEGORY.IncomingCall)
        return "phone-incoming";
    if (c === CATEGORY.MissedCall)
        return "phone-missed";
    if (c === CATEGORY.Voicemail)
        return "voicemail";
    return _APP_ICONS[_str(bundleId).toLowerCase()] || "smartphone";
}

// The fields NotificationService.notifyPhone() hands model.js's add(). The
// bridge's own record rides along under `phone` untouched, which is what
// dedupe and the dismiss sync read; `summary`/`body` are only what a card
// shows. A ringing call is critical so it stays up until the phone says it
// ended; nothing here claims `local`, so a critical phone entry still waits
// behind DND like any other app's.
function toNotification(entry) {
    var label = categoryLabel(entry.category);
    var body = entry.subtitle !== "" ? entry.subtitle + "\n" + entry.body : entry.body;
    var actions = [];
    if (entry.positiveAction !== "")
        actions.push({ key: "positive", label: entry.positiveAction });
    if (entry.negativeAction !== "")
        actions.push({ key: "negative", label: entry.negativeAction });
    return {
        appName: entry.appName,
        summary: entry.title !== "" ? entry.title : (label !== "" ? label : entry.appName),
        body: body,
        urgency: (entry.category === CATEGORY.IncomingCall || entry.important) ? 2 : 1,
        actions: actions,
        category: entry.category === CATEGORY.Social ? "im.received" : "",
        phone: {
            id: entry.id,
            bundleId: entry.bundleId,
            title: entry.title,
            subtitle: entry.subtitle,
            body: entry.body,
            icon: appIcon(entry.bundleId, entry.category),
            category: entry.category,
            session: entry.session,
            deviceHandle: entry.deviceHandle,
            positiveAction: entry.positiveAction,
            negativeAction: entry.negativeAction,
            silent: entry.silent
        }
    };
}

// One `omarchy-iphone-ams listen`/`command` stdout line to one event, or
// null for a blank line or bad JSON (omarchy-iphone @ 586f37d, bin/omarchy-
// iphone-ams). AMS rides the same BLE link as ANCS but is a second GATT
// client with its own process; `status.available` is whether the phone's
// entity-update characteristic was found at all (false right after a
// listen that then exits non-zero), and every `nowplaying` line carries the
// player's *whole* known state, not a diff, so a title-only change still
// repeats the last `elapsed`/`playback` the caller already had.
function parseAmsLine(line) {
    var text = _str(line).trim();
    if (text === "")
        return null;
    var raw;
    try {
        raw = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!raw || typeof raw !== "object")
        return null;

    switch (raw.type) {
    case "status":
        return { type: "status", available: raw.available === true };
    case "nowplaying":
        var duration = Number(raw.duration);
        var elapsed = Number(raw.elapsed);
        var volume = Number(raw.volume);
        return {
            type: "nowplaying",
            title: _str(raw.title),
            artist: _str(raw.artist),
            album: _str(raw.album),
            duration: isFinite(duration) && duration > 0 ? duration : 0,
            elapsed: isFinite(elapsed) && elapsed >= 0 ? elapsed : 0,
            playback: _str(raw.playback),
            volume: isFinite(volume) && volume >= 0 ? volume : -1
        };
    case "error":
        return { type: "error", message: explainError(raw.message) };
    }
    return null;
}

// A BlueZ device object path ends in dev_AA_BB_CC_DD_EE_FF; that is the
// device's address, which is how the phone is found among Quickshell's
// Bluetooth devices when no object path is exposed to match on directly.
function addressFromHandle(handle) {
    var m = _str(handle).match(/dev_([0-9A-Fa-f]{2}(?:_[0-9A-Fa-f]{2}){5})$/);
    return m ? m[1].replace(/_/g, ":").toUpperCase() : "";
}

// The Quickshell BluetoothDevice that is the phone: its object path first
// (the bridge's `deviceHandle` is exactly that), then the address encoded
// in it or the address of the bond the bridge reports, then the bridge's
// reported name. null when none match.
function matchDevice(devices, handle, name, bondAddress) {
    var list = devices || [];
    var address = addressFromHandle(handle) || _str(bondAddress).toUpperCase();
    var i;
    if (_str(handle) !== "") {
        for (i = 0; i < list.length; i++)
            if (_str(list[i].dbusPath) === handle)
                return list[i];
    }
    if (address !== "") {
        for (i = 0; i < list.length; i++)
            if (_str(list[i].address).toUpperCase() === address)
                return list[i];
    }
    if (_str(name) !== "") {
        for (i = 0; i < list.length; i++)
            if (list[i].connected && (_str(list[i].name) === name || _str(list[i].deviceName) === name))
                return list[i];
    }
    return null;
}

// Whether an action on this entry can still reach the phone. ancs4linux
// picks a fresh id base per connection, so an id from an earlier session
// names a notification the phone never had: the write succeeds and does
// nothing.
function isActionable(entry, currentSession) {
    if (!entry || _str(entry.deviceHandle) === "")
        return false;
    var current = _int(currentSession);
    if (current === 0)
        return true;
    return _int(entry.session) === current;
}

// AMS carries no artwork, so the phone's cover is looked up on iTunes'
// search by title and artist. Only a result by the same artist counts (a
// "Waves" by anyone else is not this track's cover); one on the same album
// wins over the first. The 100px thumbnail URL takes any size in its last
// path segment, so it is asked for at 600px. "" for no usable result.
function artworkSearchUrl(artist, title) {
    var query = (_str(title) + " " + _str(artist)).trim();
    return "https://itunes.apple.com/search?term=" + encodeURIComponent(query) + "&entity=song&limit=10";
}

function pickArtwork(body, artist, album) {
    var results;
    try {
        results = JSON.parse(body).results;
    } catch (e) {
        return "";
    }
    if (!Array.isArray(results))
        return "";
    var wantArtist = _str(artist).toLowerCase();
    var wantAlbum = _str(album).toLowerCase();
    if (wantArtist === "")
        return "";
    var first = "";
    for (var i = 0; i < results.length; i++) {
        var r = results[i] || {};
        var have = _str(r.artistName).toLowerCase();
        var url = _str(r.artworkUrl100);
        if (url === "" || have === "" || (have.indexOf(wantArtist) === -1 && wantArtist.indexOf(have) === -1))
            continue;
        url = url.replace(/\/\d+x\d+bb\.(jpg|png)$/, "/600x600bb.$1");
        if (wantAlbum !== "" && _str(r.collectionName).toLowerCase() === wantAlbum)
            return url;
        if (first === "")
            first = url;
    }
    return first;
}

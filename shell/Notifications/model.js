.pragma library

// Pure three-tier notification state machine: popups (visible toasts) ->
// pending (unseen, waiting in the history center) -> past (seen, pruned
// after 15 minutes). Every function takes state in, returns state out —
// no Date.now(), no mutation of the input.

var MAX_POPUPS = 4;
var DEFAULT_TIMEOUT_MS = 6000;
var PAST_TTL_MS = 15 * 60 * 1000;

function initialState() {
    return { popups: [], pending: [], past: [], dnd: false, nextExpiry: null };
}

// Omarchy's narrow bypass: only urgency=critical notifications from
// notify-send itself get through DND. A chat app marking its messages
// critical does not qualify — senderIsNotifySend is set by the server
// layer from the sender's app info, never inferred from urgency alone.
// A shell-authored local entry (NotificationService.notify(), M16 Task 5's
// critical battery warning) earns the same bypass on its own honest
// `local` marker — it never claims to be notify-send.
function bypassesDnd(notif) {
    return notif.urgency === 2 && (notif.senderIsNotifySend === true || notif.local === true);
}

function makeEntry(notif, now, expiresAt) {
    return {
        id: notif.id,
        appName: notif.appName,
        appIcon: notif.appIcon,
        summary: notif.summary,
        body: notif.body,
        urgency: notif.urgency,
        actions: notif.actions || [],
        image: notif.image || "",
        local: notif.local === true,
        arrivedAt: now,
        seenAt: null,
        expiresAt: expiresAt
    };
}

// null once there are no timed popups left; a sticky (expiresAt === 0)
// critical popup never contributes a deadline.
function recomputeNextExpiry(popups) {
    var next = null;
    popups.forEach(function (p) {
        if (p.expiresAt === 0) return;
        if (next === null || p.expiresAt < next) next = p.expiresAt;
    });
    return next;
}

function add(state, notif, now, opts) {
    opts = opts || {};

    if (state.dnd && !bypassesDnd(notif)) {
        return Object.assign({}, state, {
            pending: state.pending.concat([makeEntry(notif, now, null)])
        });
    }

    var timeoutMs = opts.timeoutMs !== undefined ? opts.timeoutMs : DEFAULT_TIMEOUT_MS;
    var expiresAt = notif.urgency === 2 ? 0 : now + timeoutMs;
    var popups = state.popups.concat([makeEntry(notif, now, expiresAt)]);
    var pending = state.pending;

    if (popups.length > MAX_POPUPS) {
        var overflow = popups.length - MAX_POPUPS;
        pending = pending.concat(popups.slice(0, overflow));
        popups = popups.slice(overflow);
    }

    return Object.assign({}, state, {
        popups: popups,
        pending: pending,
        nextExpiry: recomputeNextExpiry(popups)
    });
}

// Applies a replaces_id update (the server mutates the existing
// Notification object in place instead of emitting a new one — see
// NotificationService.qml's onNotification comment) to whichever tier
// currently holds the entry, without moving it between tiers or touching
// arrivedAt/seenAt. A still-popped-up entry gets expiresAt recomputed from
// the patched urgency exactly like add() does, so a later update isn't
// silently cut off by the original arrival's clock.
function update(state, id, patch, now) {
    var idx = state.popups.findIndex(function (p) { return p.id === id; });
    if (idx >= 0) {
        var popups = state.popups.slice();
        var entry = Object.assign({}, popups[idx], patch);
        entry.expiresAt = entry.urgency === 2 ? 0 : now + DEFAULT_TIMEOUT_MS;
        popups[idx] = entry;
        return Object.assign({}, state, { popups: popups, nextExpiry: recomputeNextExpiry(popups) });
    }

    idx = state.pending.findIndex(function (p) { return p.id === id; });
    if (idx >= 0) {
        var pending = state.pending.slice();
        pending[idx] = Object.assign({}, pending[idx], patch);
        return Object.assign({}, state, { pending: pending });
    }

    idx = state.past.findIndex(function (p) { return p.id === id; });
    if (idx >= 0) {
        var past = state.past.slice();
        past[idx] = Object.assign({}, past[idx], patch);
        return Object.assign({}, state, { past: past });
    }

    return state;
}

function expire(state, now) {
    var popups = [];
    var timedOut = [];
    state.popups.forEach(function (p) {
        if (p.expiresAt !== 0 && p.expiresAt <= now) timedOut.push(p);
        else popups.push(p);
    });
    if (timedOut.length === 0) return state;

    return Object.assign({}, state, {
        popups: popups,
        pending: state.pending.concat(timedOut),
        nextExpiry: recomputeNextExpiry(popups)
    });
}

// Only removes from the popups tier, marking the entry seen on its way
// to past — this is the toast surface's dismiss ("X" cell, or the click
// that acknowledges a popup still on screen).
function dismissPopup(state, id, now) {
    var idx = state.popups.findIndex(function (p) { return p.id === id; });
    if (idx < 0) return state;

    var entry = Object.assign({}, state.popups[idx], { seenAt: now });
    var popups = state.popups.slice(0, idx).concat(state.popups.slice(idx + 1));

    return Object.assign({}, state, {
        popups: popups,
        past: state.past.concat([entry]),
        nextExpiry: recomputeNextExpiry(popups)
    });
}

function markAllSeen(state, now) {
    if (state.pending.length === 0) return state;
    var seen = state.pending.map(function (p) { return Object.assign({}, p, { seenAt: now }); });
    return Object.assign({}, state, { pending: [], past: state.past.concat(seen) });
}

function prunePast(state, now) {
    var cutoff = now - PAST_TTL_MS;
    var kept = state.past.filter(function (p) {
        var at = p.seenAt !== null ? p.seenAt : p.arrivedAt;
        return at >= cutoff;
    });
    if (kept.length === state.past.length) return state;
    return Object.assign({}, state, { past: kept });
}

// General-purpose delete by id from whichever tier holds it (the history
// center's per-row dismiss, on pending or past rows) — unlike
// dismissPopup, this drops the entry outright rather than promoting it.
function dismissOne(state, id) {
    var popups = state.popups.filter(function (p) { return p.id !== id; });
    var pending = state.pending.filter(function (p) { return p.id !== id; });
    var past = state.past.filter(function (p) { return p.id !== id; });
    if (popups.length === state.popups.length &&
        pending.length === state.pending.length &&
        past.length === state.past.length) {
        return state;
    }
    return Object.assign({}, state, {
        popups: popups,
        pending: pending,
        past: past,
        nextExpiry: popups.length === state.popups.length ? state.nextExpiry : recomputeNextExpiry(popups)
    });
}

function dismissAll(state) {
    if (state.popups.length === 0) return state;
    return Object.assign({}, state, { popups: [], nextExpiry: null });
}

function clearPending(state) {
    if (state.pending.length === 0) return state;
    return Object.assign({}, state, { pending: [] });
}

// Chromium-derived sender detection and the body prefix strip below are
// ported from omarchy's NotificationLogic.js (MIT, Copyright (c) David
// Heinemeier Hansson): GitHub web notifications (and any other Chromium
// browser notification) arrive with a URL-as-link or bare-URL line glued
// to the front of the body, which is what made GH notifs unreadable.
var _CHROMIUM_MARKERS = ["chrom", "brave", "vivaldi", "microsoft-edge", "opera"];

function isChromiumDerived(appName, appIcon) {
    var source = (String(appName || "") + "\n" + String(appIcon || "")).toLowerCase();
    return _CHROMIUM_MARKERS.some(function (marker) { return source.indexOf(marker) >= 0; });
}

var _IMG_TAG_RE = /<img[^>]*>/gi;
var _CHROMIUM_LINK_PREFIX_RE = /^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i;
var _CHROMIUM_BARE_URL_PREFIX_RE = /^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i;

// <img> tags are always stripped (Center/toasts render the notification's
// own image via a dedicated icon slot, never inline in body text); the
// Chromium URL-prefix strip only applies once isChromiumDerived matches.
function sanitizeBody(body, appName, appIcon) {
    var text = String(body || "").replace(_IMG_TAG_RE, "");
    if (!isChromiumDerived(appName, appIcon)) return text;
    return text
        .replace(_CHROMIUM_LINK_PREFIX_RE, "")
        .replace(_CHROMIUM_BARE_URL_PREFIX_RE, "");
}

var _HTML_ESCAPE_RE = /[&<>]/g;
var _HTML_ESCAPE_MAP = { "&": "&amp;", "<": "&lt;", ">": "&gt;" };

function _escapeHtml(text) {
    return text.replace(_HTML_ESCAPE_RE, function (ch) { return _HTML_ESCAPE_MAP[ch]; });
}

// sanitizeBody() plus the two further transforms StyledText needs: the
// server advertises no body-markup capability (NotificationService.qml's
// NotificationServer leaves bodyMarkupSupported at its false default), so
// senders are never told markup is safe to send and any `&`/`<`/`>` in
// their text is incidental, not intentional tags — escape it first or
// Text.StyledText's parser silently swallows everything after a bare `<`
// (an unterminated tag) or misreads it as real markup. Only then does raw
// \n become <br/>, since StyledText otherwise ignores it — the <br/> we
// insert is deliberately unescaped, it's the one piece of markup this
// pipeline actually means to emit.
function styledBody(body, appName, appIcon) {
    return _escapeHtml(sanitizeBody(body, appName, appIcon)).replace(/\r\n|\r|\n/g, "<br/>");
}

// now/Nm/Nh/Nd ago, each unit's own upper bound exclusive so an exact
// hour reads "1h ago" rather than "60m ago", not the previous unit
// forever (the "600m ago" bug this replaces).
function relTime(nowMs, arrivedAtMs) {
    var diff = Math.max(0, nowMs - arrivedAtMs);
    var minute = 60 * 1000;
    var hour = 60 * minute;
    var day = 24 * hour;
    if (diff < minute) return "now";
    if (diff < hour) return Math.floor(diff / minute) + "m ago";
    if (diff < day) return Math.floor(diff / hour) + "h ago";
    return Math.floor(diff / day) + "d ago";
}

function setDnd(state, on) {
    if (state.dnd === on) return state;
    return Object.assign({}, state, { dnd: on });
}

// Not a reducer step — returns the entry itself (or null) for invokeLast:
// the most recently arrived notification still live in popups or pending.
function invokeTarget(state) {
    return state.popups.concat(state.pending).reduce(function (latest, entry) {
        return (latest === null || entry.arrivedAt > latest.arrivedAt) ? entry : latest;
    }, null);
}

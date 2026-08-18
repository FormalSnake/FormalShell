.pragma library

// Pure three-tier notification state machine: popups (visible toasts) ->
// pending (unseen, waiting in the history center) -> past (seen, pruned
// after 15 minutes). Every function takes state in, returns state out —
// no Date.now(), no mutation of the input.

// Caps GROUPS on screen, not raw entries: five repeats of one notification
// must not evict four unrelated toasts.
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

// Identical means same appName (case- and surrounding-whitespace-insensitive)
// plus same summary. Body is deliberately out of the key: the case grouping
// exists for is a chat app firing one summary with a different body per
// message, and keying on body too would degenerate to no grouping at all
// there. The NUL separator can't appear in either field, so no appName/summary
// pair can collide with a different one.
function groupKey(entry) {
    return String(entry.appName || "").trim().toLowerCase() + "\u0000" + String(entry.summary || "");
}

// Collapses repeats into one row each: a copy of the group's newest member
// carrying `count` and `memberIds` (oldest-first). Group order follows each
// group's newest member's position in `entries`, so a repeat moves its whole
// group to the newest slot instead of adding a row, and a newest-first input
// (Center.qml's reversed `past`) stays newest-first on the way out.
//
// The newest member is the one with the strictly greatest arrivedAt; a tie
// keeps whichever came first in `entries`.
//
// Grouping is DERIVED here, never stored: every entry keeps its own server id
// and its own expiresAt, so NotificationService's three id-keyed side maps
// (_live, _selfClosing, _hoveredPopups) keep resolving and each member still
// times out on its own clock. Merging entries inside makeEntry/add instead
// would orphan one of the live Notification objects: its sender would never
// be told it closed.
function groupEntries(entries) {
    var groups = [];
    var byKey = {};

    entries.forEach(function (entry, index) {
        var key = groupKey(entry);
        var group = byKey[key];
        if (group === undefined) {
            group = { members: [], newest: entry, newestIndex: index };
            byKey[key] = group;
            groups.push(group);
        } else if (entry.arrivedAt > group.newest.arrivedAt) {
            group.newest = entry;
            group.newestIndex = index;
        }
        group.members.push({ entry: entry, index: index });
    });

    // newestIndex is unique per group, so this sort never needs stability
    // (the QML JS engine's own guarantee is not worth relying on).
    groups.sort(function (a, b) { return a.newestIndex - b.newestIndex; });

    return groups.map(function (group) {
        var oldestFirst = group.members.slice().sort(function (a, b) {
            return (a.entry.arrivedAt - b.entry.arrivedAt) || (a.index - b.index);
        });
        return Object.assign({}, group.newest, {
            count: oldestFirst.length,
            memberIds: oldestFirst.map(function (m) { return m.entry.id; })
        });
    });
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

    // The whole oldest GROUP moves to pending together, order preserved in
    // both tiers, so a repeat never costs an unrelated toast its slot.
    var groups = groupEntries(popups);
    if (groups.length > MAX_POPUPS) {
        var evicted = {};
        groups.slice(0, groups.length - MAX_POPUPS).forEach(function (g) {
            g.memberIds.forEach(function (id) { evicted[id] = true; });
        });
        pending = pending.concat(popups.filter(function (p) { return evicted[p.id]; }));
        popups = popups.filter(function (p) { return !evicted[p.id]; });
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

// dismissPopup for a whole group: archives every listed id from popups to
// past in one transition, recomputing nextExpiry once. Ids not in popups are
// skipped.
function dismissPopupMany(state, ids, now) {
    var wanted = {};
    ids.forEach(function (id) { wanted[id] = true; });

    var popups = [];
    var archived = [];
    state.popups.forEach(function (p) {
        if (wanted[p.id]) archived.push(Object.assign({}, p, { seenAt: now }));
        else popups.push(p);
    });
    if (archived.length === 0) return state;

    return Object.assign({}, state, {
        popups: popups,
        past: state.past.concat(archived),
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

// dismissOne for a whole group: the history center's per-row dismiss, where
// one row can stand for several notifications.
function dismissMany(state, ids) {
    var wanted = {};
    ids.forEach(function (id) { wanted[id] = true; });
    function keep(p) { return !wanted[p.id]; }

    var popups = state.popups.filter(keep);
    var pending = state.pending.filter(keep);
    var past = state.past.filter(keep);
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

// Config-driven popup corner (DESIGN.md §Notifications, M34 Task 1):
// notifications.position, one of the four screen corners. Pure resolver, no
// Quickshell access, so Toasts.qml's PanelWindow anchors/margins, the
// column's stacking order and the enter/exit slide direction all read off
// one object instead of re-deriving corner math independently. An unknown
// or missing name falls back to the shipped default rather than erroring.
var POSITIONS = ["top-right", "bottom-right", "bottom-left", "top-left"];
var DEFAULT_POSITION = "bottom-right";

// Collapsed-stack front-to-back order (DESIGN.md §Notifications, M34 Task
// 2, sonner's depth stack translated to stepped-integer sizing): newest
// group first, EXCEPT a critical group always wins the front slot over a
// newer normal one — "urgency outranks recency at a glance". Ties (two
// criticals) resolve by recency same as everything else. Pure and
// independent of anchor direction/newestFirst — Toasts.qml's collapsed
// layout reads index 0 as the front card, 1/2 as the two peek levels, the
// rest as present only in the count the expanded stack reveals.
function stackOrder(entries) {
    var sorted = entries.slice().sort(function (a, b) { return b.arrivedAt - a.arrivedAt; });
    var criticalIdx = -1;
    for (var i = 0; i < sorted.length; i++) {
        if (sorted[i].urgency === 2) { criticalIdx = i; break; }
    }
    if (criticalIdx <= 0)
        return sorted;
    var front = sorted[criticalIdx];
    return [front].concat(sorted.slice(0, criticalIdx), sorted.slice(criticalIdx + 1));
}

function positionSpec(name) {
    var pos = POSITIONS.indexOf(name) >= 0 ? name : DEFAULT_POSITION;
    var top = pos.indexOf("top-") === 0;
    var right = pos.indexOf("-right") > 0;
    return {
        name: pos,
        top: top,
        bottom: !top,
        left: !right,
        right: right,
        // The newest toast sits nearest the anchored corner. The Column
        // always lays its children out top-down; a top-anchored window's
        // own top edge IS the anchor point, so newest needs to lead the
        // list. A bottom-anchored window's bottom edge is the anchor point,
        // which is already where groupEntries' own oldest-first order
        // lands its newest (last) entry, so no reorder is needed there.
        newestFirst: top,
        // Enter/exit slide direction (DESIGN.md §4.2: "right-anchored
        // surfaces slide in from the right", generalized to a left-anchored
        // stack sliding in from the left).
        slideSign: right ? 1 : -1
    };
}

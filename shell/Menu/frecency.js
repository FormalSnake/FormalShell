.pragma library

// Launch-frequency ranking for the menu's app rows: how OFTEN an app gets
// launched, weighted by how RECENTLY. Pure and dependency-free so it's
// testable head-on (tests/tst_frecency.qml), same shape as usage.js and
// Visualizer/model.js.
//
// Store shape: [{ id, count, lastMs }], keyed on the DESKTOP ENTRY id
// (`entry.id`, the same value providers.js:32 builds its node ids from).
// An array of records rather than an id-keyed object because that's the
// shape a JsonAdapter `var` property is already proven to round-trip in
// this shell (ClipboardService.qml's own `property var items: []`
// history). It lives in $XDG_STATE_HOME/formalshell/state.json via
// Core/State.qml: a launch count is runtime-mutable state by definition,
// and settings.json is read-only (CLAUDE.md hard rule).
//
// The score is the smallest thing that answers both halves of the question:
// `count` multiplied by an exponential recency decay of half-life
// HALF_LIFE_MS. A never-launched entry scores exactly 0 (no "slightly
// better than nothing" bias over an app the user has genuinely never
// touched), and four launches a month ago lose to one this morning. No
// per-launch history, no session weighting, no time-of-day buckets, none
// of that is explainable from a state.json a user can read.
//
// What this deliberately does NOT do is outrank the fuzzy search.
// providers.js's appsProvider only uses order() to decide the order it
// hands its rows to the tree in, and search.js:85-89 breaks equal-score
// ties by declaration order, so frecency picks which of two
// equally-good matches leads, and nothing else. A stronger match tier
// still wins outright, exactly as it did before.

var HALF_LIFE_MS = 14 * 24 * 60 * 60 * 1000;

// The ledger grows by at most one id per distinct app ever launched and
// never shrinks on its own, so an app uninstalled two years ago would keep
// its record in state.json forever. Capping by current score on write is
// the whole of the hygiene: the entries dropped are, by construction, the
// ones that lost both halves of the question.
var MAX_ENTRIES = 200;

function _scoreOf(record, nowMs) {
    if (!record) return 0;
    var count = Number(record.count);
    if (!isFinite(count) || count <= 0) return 0;
    var last = Number(record.lastMs);
    // A record with no usable timestamp decays not at all, rather than
    // decaying to nothing: state.json is hand-editable, and a missing
    // `lastMs` is missing information, not a launch in 1970.
    var age = (isFinite(last) && last > 0) ? Math.max(0, Number(nowMs) - last) : 0;
    return count * Math.pow(0.5, age / HALF_LIFE_MS);
}

function _index(store) {
    var out = {};
    for (var i = 0; i < (store || []).length; i++) {
        var record = store[i];
        if (!record) continue;
        var id = String(record.id || "");
        if (id !== "") out[id] = record;
    }
    return out;
}

// 0 for anything this store has never seen, the honest answer for an app
// with no launch history, never a floor above it.
function score(store, id, nowMs) {
    return _scoreOf(_index(store)[String(id || "")], nowMs);
}

// Returns a NEW store, never mutating the argument: Core/State.qml's
// JsonAdapter only writes on assignment, and QML's var-property change
// detection compares references, so an in-place bump would persist
// nothing and rebuild nothing.
function record(store, id, nowMs, maxEntries) {
    var key = String(id || "");
    var out = [];
    var bumped = false;
    for (var i = 0; i < (store || []).length; i++) {
        var entry = store[i];
        if (!entry) continue;
        var entryId = String(entry.id || "");
        if (entryId === "") continue;
        if (entryId === key) {
            bumped = true;
            out.push({ id: key, count: (Number(entry.count) || 0) + 1, lastMs: nowMs });
        } else {
            out.push({ id: entryId, count: Number(entry.count) || 0, lastMs: Number(entry.lastMs) || 0 });
        }
    }
    if (key === "") return out;
    if (!bumped) out.push({ id: key, count: 1, lastMs: nowMs });
    return _cap(out, nowMs, maxEntries === undefined ? MAX_ENTRIES : maxEntries);
}

function _cap(list, nowMs, maxEntries) {
    if (list.length <= maxEntries) return list;
    list.sort(function (a, b) { return _scoreOf(b, nowMs) - _scoreOf(a, nowMs); });
    return list.slice(0, maxEntries);
}

// Stable reorder of `items` (anything carrying an `id`) by descending
// score, ties keeping the caller's own order, the QML JS engine's sort
// isn't specified stable, hence the explicit original-position tiebreak.
// An empty/absent store leaves the input order completely untouched, so a
// fresh profile browses apps in exactly the order it did before.
//
// `idOf` reads the ledger key off an item that doesn't carry one as `id`:
// the emoji route ranks dataset entries ({ch, name, group}) before it has
// built a row for any of them, and building one just to read its id would
// undo the memoisation that keeps that route cheap (providers.js's own
// header). Omitted, items are keyed on `item.id` as before.
function order(items, store, nowMs, idOf) {
    var index = _index(store);
    var decorated = [];
    for (var i = 0; i < (items || []).length; i++) {
        var item = items[i];
        var id = item ? (idOf ? idOf(item) : item.id) : "";
        decorated.push({
            item: item,
            position: i,
            score: item ? _scoreOf(index[String(id || "")], nowMs) : 0
        });
    }
    decorated.sort(function (a, b) {
        if (b.score !== a.score) return b.score - a.score;
        return a.position - b.position;
    });
    return decorated.map(function (d) { return d.item; });
}

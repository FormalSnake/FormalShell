.pragma library

// Pure clipboard-history reducer: capped, de-duplicated by content, newest
// first. Every function takes state in, returns state out — no Date.now(),
// no mutation of the input (mirrors Notifications/model.js).

var MAX_ENTRIES = 300;

function initialState() {
    return { items: [] };
}

// Drops empty/whitespace-only captures — the shape a CLIPBOARD_STATE=nil/
// clear watch event produces (stdin attached to /dev/null) — and returns the
// text unchanged otherwise; sanitize never trims real content.
function sanitize(text) {
    if (typeof text !== "string") return null;
    return text.trim().length === 0 ? null : text;
}

// Re-copying content already in history moves the existing entry to the
// front (refreshing capturedAt) instead of inserting a duplicate — the new
// entry keeps the OLD id, so anything holding a reference to it (a pending
// copy(id)/remove(id)) still resolves.
function add(state, entry, now) {
    var text = sanitize(entry.text);
    if (text === null) return state;

    var items = state.items;
    var idx = items.findIndex(function (i) { return i.text === text; });
    var id = entry.id;
    if (idx >= 0) {
        id = items[idx].id;
        items = items.slice(0, idx).concat(items.slice(idx + 1));
    }

    items = [{ id: id, text: text, capturedAt: now }].concat(items);
    if (items.length > MAX_ENTRIES) items = items.slice(0, MAX_ENTRIES);

    return Object.assign({}, state, { items: items });
}

function remove(state, id) {
    var items = state.items.filter(function (i) { return i.id !== id; });
    if (items.length === state.items.length) return state;
    return Object.assign({}, state, { items: items });
}

function clear(state) {
    if (state.items.length === 0) return state;
    return Object.assign({}, state, { items: [] });
}

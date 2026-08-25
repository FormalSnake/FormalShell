.pragma library

// Pure clipboard-history reducer: capped, de-duplicated by content, newest
// first. Every function takes state in, returns state out, no Date.now(),
// no mutation of the input (mirrors Notifications/model.js). Entries carry
// a `kind` ("text" | "image"); entries persisted before images existed
// (M14 Task 1) have no `kind` field at all, normalizeEntry() reads those
// as text on load, a pure migration with no file rewrite pass. Image
// entries dedupe by `path` instead of content: the capture side content-
// addresses the file by its sha256 upstream (Task 6), so path equality
// already IS content equality. The mutating reducers (add/remove/clear)
// return `{state, removedPaths}`, the image paths any eviction just
// orphaned, history.js stays pure and never touches the filesystem
// itself; ClipboardService is the one that deletes removedPaths.

var MAX_ENTRIES = 300;

function initialState() {
    return { items: [] };
}

function _noRemoval(state) {
    return { state: state, removedPaths: [] };
}

// Drops empty/whitespace-only captures, the shape a CLIPBOARD_STATE=nil/
// clear watch event produces (stdin attached to /dev/null), and returns the
// text unchanged otherwise; sanitize never trims real content.
function sanitize(text) {
    if (typeof text !== "string") return null;
    return text.trim().length === 0 ? null : text;
}

// Legacy entries (persisted before images existed) carry no `kind` field,
// read those as text. Pure and idempotent; never rewrites the file.
function normalizeEntry(entry) {
    if (entry.kind === "text" || entry.kind === "image") return entry;
    return Object.assign({}, entry, { kind: "text" });
}

function _imagePathsOf(entries) {
    return entries.filter(function (i) { return i.kind === "image"; }).map(function (i) { return i.path; });
}

function _capOverflow(items) {
    if (items.length <= MAX_ENTRIES) return { items: items, removedPaths: [] };
    var overflow = items.slice(MAX_ENTRIES);
    return { items: items.slice(0, MAX_ENTRIES), removedPaths: _imagePathsOf(overflow) };
}

// Re-copying content already in history moves the existing entry to the
// front (refreshing capturedAt) instead of inserting a duplicate, the new
// entry keeps the OLD id, so anything holding a reference to it (a pending
// copy(id)/remove(id)) still resolves.
function _addText(state, entry, now) {
    var text = sanitize(entry.text);
    if (text === null) return _noRemoval(state);

    var items = state.items;
    var idx = items.findIndex(function (i) { return i.kind !== "image" && i.text === text; });
    var id = entry.id;
    if (idx >= 0) {
        id = items[idx].id;
        items = items.slice(0, idx).concat(items.slice(idx + 1));
    }

    items = [{ id: id, kind: "text", text: text, capturedAt: now }].concat(items);
    var capped = _capOverflow(items);
    return { state: Object.assign({}, state, { items: capped.items }), removedPaths: capped.removedPaths };
}

// Images dedupe by path, not by re-hashing content here, the capture side
// already content-addresses the file by sha256 (Task 6), so path equality
// IS content equality.
function _addImage(state, entry, now) {
    if (!entry.path) return _noRemoval(state);

    var items = state.items;
    var idx = items.findIndex(function (i) { return i.kind === "image" && i.path === entry.path; });
    var id = entry.id;
    if (idx >= 0) {
        id = items[idx].id;
        items = items.slice(0, idx).concat(items.slice(idx + 1));
    }

    items = [{ id: id, kind: "image", path: entry.path, mime: entry.mime || "image/png", capturedAt: now }].concat(items);
    var capped = _capOverflow(items);
    return { state: Object.assign({}, state, { items: capped.items }), removedPaths: capped.removedPaths };
}

function add(state, entry, now) {
    return entry.kind === "image" ? _addImage(state, entry, now) : _addText(state, entry, now);
}

function remove(state, id) {
    var idx = state.items.findIndex(function (i) { return i.id === id; });
    if (idx < 0) return _noRemoval(state);

    var removed = state.items[idx];
    var items = state.items.slice(0, idx).concat(state.items.slice(idx + 1));
    return {
        state: Object.assign({}, state, { items: items }),
        removedPaths: removed.kind === "image" ? [removed.path] : []
    };
}

function clear(state) {
    if (state.items.length === 0) return _noRemoval(state);
    return { state: Object.assign({}, state, { items: [] }), removedPaths: _imagePathsOf(state.items) };
}

.pragma library

// Which running windows belong to a DesktopEntry, so activating an app row
// in the menu focuses the app you already have open instead of spawning a
// second copy. Pure, so it's testable head-on (tests/tst_app_match.qml),
// and it needs no backend work at all: CompositorService.focusWindow(id)
// and CompositorService.windows (rows carrying `appId`) already exist on
// both compositors.
//
// Only two DesktopEntry fields are read, and both are the ones quickshell
// itself matches on. From the pinned quickshell input
// (/nix/store/zxnaal0jk0qcha2z2nbcdi8cya9iz4bz-source, rev 43d4fa9):
// src/core/desktopentry.hpp:58-60 documents `startupClass` as the "initial
// class or app id the app intends to use", and
// DesktopEntryManager::heuristicLookup (desktopentry.cpp:447-464) runs this
// same comparison in reverse: by id, then exact startupClass, then
// case-insensitive startupClass. `id` is the .desktop basename with the
// extension stripped (desktopentry.cpp:396-397), which equals the app_id
// for the large majority of Linux apps.
//
// There is deliberately no third fuzzy tier (no reverse-DNS tail matching,
// no substring). Electron apps and wrapper-launched apps commonly report an
// app_id unrelated to their .desktop basename, and chasing that tail buys a
// worse failure: a miss falls through to the caller's existing spawn path,
// which is today's behaviour, while a fuzzy hit focuses the wrong app.
//
// Opaque-id rule: window `appId` strings are compared, window `id` strings
// are copied into the result verbatim and never parsed, ordered by, or
// compared numerically.

// One tier's comparison across every window, in `windows` order. An empty
// appId never matches, so a window the compositor has not classified can
// not be claimed by an entry with an empty startupClass.
function _collect(needle, windows, fold) {
    var want = fold ? needle.toLowerCase() : needle;
    var out = [];
    for (var i = 0; i < windows.length; i++) {
        var win = windows[i] || {};
        var appId = String(win.appId || "");
        if (appId === "")
            continue;
        if ((fold ? appId.toLowerCase() : appId) === want)
            out.push(win.id);
    }
    return out;
}

// [windowId, ...] in `windows` order, or [] when nothing matched.
//
// Tiers, first non-empty tier wins outright, never a union, because a
// union would mix a precise startupClass hit with a coincidental id hit and
// then cycle between two different apps.
function matchWindows(entry, windows) {
    var wins = Array.isArray(windows) ? windows : [];
    var e = entry || {};

    var tiers = [];
    if (String(e.startupClass || "") !== "")
        tiers.push(String(e.startupClass));
    if (String(e.id || "") !== "")
        tiers.push(String(e.id));

    for (var t = 0; t < tiers.length; t++) {
        var exact = _collect(tiers[t], wins, false);
        if (exact.length > 0)
            return exact;
        var folded = _collect(tiers[t], wins, true);
        if (folded.length > 0)
            return folded;
    }
    return [];
}

// The window to focus next: the one AFTER `focusedWindowId` in `matches`,
// wrapping, so repeat-activating an app row cycles its open instances.
// Focus sitting outside `matches` (another app, or nothing focused) starts
// the cycle at the first instance.
function nextWindow(matches, focusedWindowId) {
    var m = Array.isArray(matches) ? matches : [];
    if (m.length === 0)
        return "";
    var at = m.indexOf(focusedWindowId);
    return (at === -1) ? m[0] : m[(at + 1) % m.length];
}

// Marks the menu's app rows that would focus rather than launch. Returns a
// new array of new row objects so the tree nodes providers.js built stay
// the pure data they are; `desc` is MenuRow.qml's dim trailing slot.
function decorateAppRows(rows, windows) {
    var src = Array.isArray(rows) ? rows : [];
    var wins = Array.isArray(windows) ? windows : [];
    return src.map(function (row) {
        var copy = Object.assign({}, row);
        if (matchWindows(row._entry, wins).length > 0)
            copy.desc = "FOCUS";
        return copy;
    });
}

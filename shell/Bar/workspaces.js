.pragma library

// Portions from omarchy-spaces (MIT, Copyright 2026 Tornike Gomareli)

// Pure model for the bar's workspace cell (M13 Task 1, M74 Task 2): which
// workspaces render, in what order, and which windows each one shows. No
// Quickshell access, so it's testable head-on (tests/tst_workspaces_model.qml).
//
// A workspace renders if it holds at least one window, is active/focused, or
// is one of the persistent slots 1..n. A compositor that declares persistent
// workspaces up front would otherwise show nine cells with two windows open.
// Occupancy is counted from the windows list by workspace id because the
// backend's workspace payload carries no occupancy field of its own. Order is
// the backend's own per-output ordinal `idx` (Hyprland's numeric id), ids
// stay opaque strings, never parsed. Workspaces on `outputName` win; when
// none match (compositor output name vs Quickshell screen name mismatch)
// every workspace is considered, grouped by output name so the fallback
// stays deterministic.
//
// A persistent slot the compositor has no workspace for at all, on any
// output, is a placeholder: `id` "", `placeholder` true, its `idx` the only
// thing it knows. Going there is `CompositorService.focusWorkspaceAt(idx)`,
// since there is no id to hand over. One that exists on another output is
// that output's, and stays off this bar.

function _slotOutput(pool, outputName, matched) {
    if (matched || pool.length === 0)
        return outputName;
    var first = pool[0].output;
    for (var i = 1; i < pool.length; i++) {
        if (pool[i].output < first)
            first = pool[i].output;
    }
    return first;
}

function visibleModel(workspaces, windows, outputName, persistent) {
    var pool = workspaces.filter(function (ws) { return ws.output === outputName; });
    var matched = pool.length > 0;
    if (!matched)
        pool = workspaces.slice();

    var occupied = {};
    for (var i = 0; i < windows.length; i++)
        occupied[windows[i].workspaceId] = true;

    var keep = Math.max(0, Math.floor(Number(persistent) || 0));
    var known = {};
    for (var k = 0; k < workspaces.length; k++)
        known[workspaces[k].idx] = true;

    var out = pool.filter(function (ws) {
        return occupied[ws.id] === true || ws.isActive || ws.isFocused || (ws.idx >= 1 && ws.idx <= keep);
    });

    var slotOutput = _slotOutput(pool, outputName, matched);
    for (var n = 1; n <= keep; n++) {
        if (known[n])
            continue;
        out.push({
            id: "",
            idx: n,
            name: "",
            output: slotOutput,
            isActive: false,
            isFocused: false,
            isUrgent: false,
            placeholder: true
        });
    }

    return out.sort(function (a, b) {
        if (a.output !== b.output)
            return a.output < b.output ? -1 : 1;
        return a.idx - b.idx;
    });
}

// Screen order: left to right, then top to bottom. A window with no box
// (the backend's `rect: null`) goes after every placed one, and ties keep
// the order the backend listed them in.
function _byPosition(a, b) {
    var ra = a.win.rect, rb = b.win.rect;
    if (ra && rb) {
        if (ra.x !== rb.x)
            return ra.x - rb.x;
        if (ra.y !== rb.y)
            return ra.y - rb.y;
    } else if (ra && !rb) {
        return -1;
    } else if (!ra && rb) {
        return 1;
    }
    return a.at - b.at;
}

// The windows one slot shows, in screen order, capped at `maxIcons` with
// the rest counted in `overflow`. The focused window is never the one the
// cap drops: past the cap it takes the last shown place instead, so the
// lit icon is always on the bar.
//
// Only the fields that pick an icon and a state ride along. The title
// changes on every keystroke in a terminal and the rect on every resize;
// carrying either would republish the whole bar model for a change nothing
// on the strip draws. Tooltips and the preview read those live by id.
function slotWindows(windows, workspaceId, maxIcons) {
    if (workspaceId === "")
        return { windows: [], overflow: 0 };
    var indexed = [];
    for (var i = 0; i < windows.length; i++) {
        if (windows[i].workspaceId === workspaceId)
            indexed.push({ win: windows[i], at: i });
    }
    indexed.sort(_byPosition);
    var cap = Math.max(1, Math.floor(Number(maxIcons) || 1));
    var shown = indexed.slice(0, cap);
    if (indexed.length > cap) {
        for (var f = cap; f < indexed.length; f++) {
            if (indexed[f].win.isFocused) {
                shown[cap - 1] = indexed[f];
                break;
            }
        }
    }
    return {
        windows: shown.map(function (e) {
            var w = e.win;
            return {
                id: w.id,
                appId: w.appId || "",
                initialClass: w.initialClass || "",
                initialTitle: w.initialTitle || "",
                pid: w.pid || 0,
                isFocused: w.isFocused === true,
                isUrgent: w.isUrgent === true
            };
        }),
        overflow: Math.max(0, indexed.length - cap)
    };
}

// What a slot is called: the workspace's own name when the compositor
// carries one, its ordinal otherwise.
function label(ws) {
    return ws.name && ws.name !== "" ? String(ws.name) : String(ws.idx);
}

// Every slot this bar draws, windows included. `current` is the workspace
// on screen on this output (focused or merely visible), which is the one
// that opens wide; `isFocused` is where the pill sits.
function slots(workspaces, windows, outputName, opts) {
    var o = opts || {};
    var visible = visibleModel(workspaces, windows, outputName, o.persistent);
    return visible.map(function (ws) {
        var list = slotWindows(windows, ws.id, o.maxIcons === undefined ? 8 : o.maxIcons);
        var urgent = ws.isUrgent === true || list.windows.some(function (w) { return w.isUrgent; });
        return {
            id: ws.id,
            idx: ws.idx,
            name: ws.name || "",
            label: label(ws),
            output: ws.output,
            isActive: ws.isActive === true,
            isFocused: ws.isFocused === true,
            current: ws.isActive === true || ws.isFocused === true,
            isUrgent: urgent,
            placeholder: ws.placeholder === true,
            windows: list.windows,
            overflow: list.overflow
        };
    });
}

// Whether a slot shows its icons. `mode` is `workspaces.showApps`: `all`,
// `active` (the current slot only) or `hover` (the current slot, and any
// other while the pointer is on it). An unknown mode reads as `hover`.
function showsApps(mode, current, hovered) {
    if (mode === "all")
        return true;
    if (mode === "active")
        return current;
    return current || hovered;
}

// The slot a wheel notch lands on, wrapping at either end; the first slot
// when none is focused here. -1 on an empty list.
function stepIndex(count, focusedIndex, delta) {
    if (count <= 0)
        return -1;
    if (focusedIndex < 0 || focusedIndex >= count)
        return 0;
    return (focusedIndex + (delta > 0 ? 1 : -1) + count) % count;
}

// Where each window sits in a `width` x `height` miniature of `area` (the
// output's logical box), at its real place on screen and clamped into the
// frame: a window hanging off the output's edge would otherwise draw
// outside the card. Floating windows come last so they draw on top, as
// they do on screen. If any window has no box, none of them has a place
// that means anything, and the lot are laid out as an even grid instead.
function previewLayout(windows, area, width, height, minSize) {
    var min = minSize > 0 ? minSize : 1;
    var placed = [];
    var n = windows.length;
    var known = !!area && area.width > 0 && area.height > 0 && n > 0
        && windows.every(function (w) { return !!w.rect; });

    if (known) {
        var sx = width / area.width;
        var sy = height / area.height;
        for (var i = 0; i < n; i++) {
            var r = windows[i].rect;
            var x = (r.x - area.x) * sx;
            var y = (r.y - area.y) * sy;
            var cx = Math.max(0, Math.min(width - min, x));
            var cy = Math.max(0, Math.min(height - min, y));
            placed.push({
                id: windows[i].id,
                x: cx,
                y: cy,
                width: Math.max(min, Math.min(width - cx, r.width * sx - (cx - x))),
                height: Math.max(min, Math.min(height - cy, r.height * sy - (cy - y))),
                floating: windows[i].isFloating === true
            });
        }
    } else if (n > 0) {
        var cols = Math.max(1, Math.ceil(Math.sqrt(n)));
        var rows = Math.max(1, Math.ceil(n / cols));
        var cw = width / cols;
        var ch = height / rows;
        for (var j = 0; j < n; j++) {
            placed.push({
                id: windows[j].id,
                x: (j % cols) * cw,
                y: Math.floor(j / cols) * ch,
                width: cw,
                height: ch,
                floating: false
            });
        }
    }

    var order = placed.map(function (p, at) { return { p: p, at: at }; });
    order.sort(function (a, b) {
        var fa = a.p.floating ? 1 : 0, fb = b.p.floating ? 1 : 0;
        return fa !== fb ? fa - fb : a.at - b.at;
    });
    return order.map(function (e) { return e.p; });
}

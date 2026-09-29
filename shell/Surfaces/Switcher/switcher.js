.pragma library

// The window switcher's list and its cursor (M60 T6, the 2026-09-17 spec's
// Part 2), pure so the order, the wrap and the empty state are testable
// without a compositor (tests/tst_switcher_model.qml).

// What the switcher offers, in Gala's order
// (`src/Widgets/WindowSwitcher/WindowSwitcher.vala`): the most recently
// focused window first, the one before it second, and so on, which is what
// makes a single Alt+Tab land on the window you just came from. `history` is
// the ids the surface has watched take focus, newest first; a window nothing
// has focused this session has no place in it and keeps the compositor's own
// order behind the ones that have.
//
// `workspaceId` is the one being looked at, and windows anywhere else are not
// offered. Gala's own list is the active workspace's:
// `handle_switch_windows` reads
// `display.get_workspace_manager ().get_active_workspace ()` and hands it to
// `collect_all_windows`, whose `display.get_tab_list (NORMAL, workspace)` is
// filtered to it. Offering the rest is what made a quick Alt+Tab land on
// another workspace and take the compositor there with it (owner,
// 2026-09-18): Gala has a branch for that case
// (`workspace.activate_with_focus`) and never reaches it, because the window
// was not on the card to begin with. Empty means no filter, the same
// convention `shell/Compositor/focus.js`'s hold takes for the same value.
//
// Special workspaces are dropped ahead of that, the same rule the workspace
// model carries (shell/Compositor/hyprland/model.js): they are overlays
// rather than places, and the quake console lives on one permanently, so a
// switcher that offered them would offer a window the user cannot see and
// never put there.
function entries(windows, history, workspaceId) {
    var list = windows || [];
    var seen = history || [];
    var here = workspaceId || "";
    var offered = [];
    for (var i = 0; i < list.length; i++) {
        var win = list[i];
        if (!win || !win.id)
            continue;
        if (String(win.workspaceId || "").indexOf("-") === 0)
            continue;
        if (here !== "" && win.workspaceId !== here)
            continue;
        offered.push(win);
    }

    var out = [];
    var taken = {};
    for (var h = 0; h < seen.length; h++) {
        for (var o = 0; o < offered.length; o++) {
            if (offered[o].id !== seen[h] || taken[seen[h]])
                continue;
            taken[seen[h]] = true;
            out.push(offered[o]);
        }
    }
    for (var r = 0; r < offered.length; r++) {
        if (!taken[offered[r].id])
            out.push(offered[r]);
    }
    return out;
}

// Where the cursor lands after a step, wrapping both ways. An empty list has
// no cursor at all, which is the index the caller holds while nothing is
// offered.
function advance(index, count, step) {
    if (!(count > 0))
        return 0;
    var next = (index + step) % count;
    return next < 0 ? next + count : next;
}

// One cell's thumbnail width at a fixed height, from the window's own rect so
// the picture keeps its aspect. A window with no rect yet reads as 16:9, and
// the ratio is held between `minWidth` and `maxWidth` so a sliver of a window
// or a very wide one still leaves a cell that can carry its caption.
function thumbWidth(rect, height, minWidth, maxWidth) {
    var ratio = rect && rect.width > 0 && rect.height > 0
        ? rect.width / rect.height : 16 / 9;
    var width = Math.round(height * ratio);
    return Math.max(minWidth, Math.min(maxWidth, width));
}

function _pack(widths, gap, limit) {
    var rows = [];
    var first = 0;
    var used = 0;
    for (var i = 0; i < widths.length; i++) {
        var next = i === first ? widths[i] : used + gap + widths[i];
        if (i > first && next > limit) {
            rows.push({ first: first, count: i - first, width: used, widths: widths.slice(first, i) });
            first = i;
            next = widths[i];
        }
        used = next;
    }
    if (widths.length > 0)
        rows.push({ first: first, count: widths.length - first, width: used, widths: widths.slice(first) });
    return rows;
}

// The cells wrapped into rows no wider than `maxWidth`, in order. A row
// count is taken from a plain greedy fill, then the limit is pulled in as far
// as that count allows, so eleven windows over two rows read as 6 and 5
// rather than as a full row and a stub. `width` is the widest row, which is
// what the card is as wide as, and each row carries its cells' widths. A cell wider than `maxWidth` still gets a row
// of its own.
function layout(widths, gap, maxWidth) {
    var list = widths || [];
    var spacing = gap || 0;
    if (list.length === 0)
        return { rows: [], width: 0, gap: spacing };
    var widest = Math.max.apply(null, list);
    var limit = Math.max(widest, Math.floor(maxWidth || 0));
    var count = _pack(list, spacing, limit).length;
    var low = widest;
    var high = limit;
    while (low < high) {
        var mid = Math.floor((low + high) / 2);
        if (_pack(list, spacing, mid).length <= count)
            high = mid;
        else
            low = mid + 1;
    }
    var rows = _pack(list, spacing, high);
    var width = 0;
    for (var i = 0; i < rows.length; i++)
        width = Math.max(width, rows[i].width);
    return { rows: rows, width: width, gap: spacing };
}

// Where each cell sits in the grid, from the top left: rows stacked at
// `cellHeight`, each centred on the widest one.
function cells(grid, cellHeight) {
    var out = [];
    for (var r = 0; r < grid.rows.length; r++) {
        var row = grid.rows[r];
        var x = (grid.width - row.width) / 2;
        for (var i = 0; i < row.count; i++) {
            var width = row.widths[i];
            out.push({ x: x, y: r * cellHeight, width: width, height: cellHeight, row: r });
            x += width + grid.gap;
        }
    }
    return out;
}

// Which row holds entry `index`, or -1 past the end.
function rowOf(rows, index) {
    for (var i = 0; i < rows.length; i++) {
        if (index >= rows[i].first && index < rows[i].first + rows[i].count)
            return i;
    }
    return -1;
}

// Which of its app's windows each tile is: `{ n, of }` per key, `n` counting
// from 1 in row order. An empty key is a window nothing could name, which
// is never grouped with another, so it reads `{ n: 1, of: 1 }`.
function ordinals(keys) {
    var list = keys || [];
    var totals = {};
    for (var i = 0; i < list.length; i++) {
        if (list[i])
            totals[list[i]] = (totals[list[i]] || 0) + 1;
    }
    var seen = {};
    var out = [];
    for (var j = 0; j < list.length; j++) {
        var key = list[j];
        if (!key) {
            out.push({ n: 1, of: 1 });
            continue;
        }
        seen[key] = (seen[key] || 0) + 1;
        out.push({ n: seen[key], of: totals[key] });
    }
    return out;
}

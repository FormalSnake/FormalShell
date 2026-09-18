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

// How wide the row is, and how many rows that leaves. `maxColumns` is what
// the card may hold across at the output's own width, so a session with more
// windows than that wraps rather than running off the screen. The rows are
// balanced instead of filled: eleven windows across a card holding seven
// read as 6 and 5 rather than as a full row and a stub.
function columns(count, maxColumns) {
    var cap = Math.max(1, Math.floor(maxColumns || 0));
    if (!(count > 0))
        return 0;
    if (count <= cap)
        return count;
    return Math.ceil(count / Math.ceil(count / cap));
}

function rows(count, cols) {
    if (!(count > 0) || !(cols > 0))
        return 0;
    return Math.ceil(count / cols);
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

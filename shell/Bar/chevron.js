// The bar chevron's fit (M52), the same shape Bar/tray.js already answers for
// the tray: does the group behind a region's chevron have room on the strip,
// or does it have to open in a second bar instead (Surfaces/Bar/BarOverflow.qml)?
//
// Pure arithmetic over measurements Bar.qml takes off its own Loaders, so the
// claim below is testable head-on (tests/tst_bar_chevron_fit.qml) rather than
// only observable in a screenshot.

// What an expanded group costs its region along the strip: every governed
// cell's own extent plus the region's `spacing`, once per cell. A Grid spaces
// between its visible children, so a region already holding at least one
// permanent cell (a chevron with nothing outboard of it does not exist,
// layout.js drops it) pays exactly one gap per cell that joins it.
function groupAlong(alongs, spacing) {
    var total = 0;
    for (var i = 0; i < alongs.length; i++)
        total += alongs[i] + spacing;
    return total;
}

// Whether that group fits. `slack` is what the strip has left over right now
// (Bar.qml's `_slack`), and `expandedNow` says whether this group is already
// part of the extent that number was worked out against.
//
// Capacity, not slack, is the invariant: whatever the group takes, the
// leftover loses, so `slack + (expanded ? need : 0)` is the same number in
// both states. That is the whole reason this converges rather than
// oscillating, exactly as the tray's own fit does: an answer of "no room"
// collapses the group, which frees room, which must NOT then read as "room
// again" on the next pass.
function fitsInline(need, slack, expandedNow) {
    if (need <= 0)
        return true;
    return slack + (expandedNow ? need : 0) >= need;
}

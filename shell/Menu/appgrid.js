.pragma library

// The launcher's app grid (M58). Pure maths for the view under
// Surfaces/Menu/views/AppGridView.qml: how many cells fit across the card,
// which rows the grid owns, and where one arrow press lands when the level
// is a grid of apps with a list of everything else under it.
//
// Nothing here knows about Theme or the row objects beyond their `kind`, so
// the column count and the cursor walk are testable head-on, the same
// arrangement search.js and frecency.js already have.

// How many cells fit across `width` at `minCell`, at least one: a card
// narrower than a single cell still draws a column rather than none. The
// grid then divides `width` by this, so the cells share the whole width and
// every gutter comes out equal, which is what the wallpaper and emoji grids
// already do.
function columnsFor(width, minCell) {
    if (!(width > 0) || !(minCell > 0))
        return 1;
    return Math.max(1, Math.floor(width / minCell));
}

// App rows first, everything else after, each block in the order the
// ranking gave it (M58 G2). A stable partition, not a sort: nothing is
// scored again here, so a query that ranked one app above another still
// draws them in that order, and the commands under the grid keep theirs.
//
// The result IS the launcher's row list, so `appCount` doubles as the index
// of the first row under the grid and every cursor index below is an index
// into one array rather than into a view.
function partition(rows) {
    rows = rows || [];
    var apps = [];
    var rest = [];
    for (var i = 0; i < rows.length; i++) {
        if (rows[i] && rows[i].kind === "app")
            apps.push(rows[i]);
        else
            rest.push(rows[i]);
    }
    if (rest.length === 0)
        return { rows: apps, appCount: apps.length };
    if (apps.length === 0)
        return { rows: rest, appCount: 0 };
    return { rows: apps.concat(rest), appCount: apps.length };
}

// What one Up or Down press actually moves the cursor by, given the step a
// pure grid would take (`delta`, plus or minus the column count). The
// caller applies the answer and wraps it, so this only decides the size of
// the step, never the destination.
//
// Three cases, and the first is the whole point: below the grid the rows
// are a list, and a list moves by a row. Down out of the grid's last row
// lands on the first row under it rather than skipping past the ones a
// column step would jump; up out of that first row lands back in the grid,
// on the cell the reader just left.
function verticalStep(delta, index, appCount, total) {
    if (!(total > 0) || delta === 0)
        return delta;
    if (index >= appCount)
        return delta > 0 ? 1 : -1;
    if (delta > 0 && appCount < total && index + delta >= appCount)
        return appCount - index;
    return delta;
}

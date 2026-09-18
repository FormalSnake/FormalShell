.pragma library

// The launcher's app grid (M58). Pure maths for the view under
// Surfaces/Menu/views/AppGridView.qml: how many cells fit across the card,
// and which rows the grid owns. Where an arrow press lands is Menu/nav.js's,
// which walks every launcher view with one set of rules.
//
// Nothing here knows about Theme or the row objects beyond their `kind`, so
// the column count and the split are testable head-on, the same
// arrangement search.js and frecency.js already have; the launcher habit
// arrives as the plain string the theme table carries.

// Whether the grid is what a level opens on with nothing set (M60 P6).
// `menu.appGrid` is read through Config with this as its default, so an
// explicit false in settings.json still wins on a table that asks for the
// grid: elementary's launcher is Slingshot's pages of icons, Omarchy's is a
// list of rows.
function defaultFor(launcherHabit) {
    return launcherHabit === "grid";
}

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

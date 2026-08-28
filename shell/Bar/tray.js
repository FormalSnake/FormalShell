.pragma library

// How much of the tray fits on the strip, and what spills into the second
// bar (Surfaces/Bar/TrayOverflow.qml). Pure, so the fit is checkable
// head-on, the same split layout.js and panels.js already take.
//
// Every tray cell is one icon in the bar's own square slot, so a single
// extent describes all of them and the fit is arithmetic rather than a
// per-cell measurement: n cells cost n * cell + (n - 1) * spacing, and the
// overflow toggle is one more cell of that same size with its own gap in
// front of it. The toggle is only charged for once something is actually
// hidden, so a tray that fits exactly still fits whole.

function extent(n, cell, spacing) {
    return n <= 0 ? 0 : n * cell + (n - 1) * spacing;
}

// `budget` is the room the rail has along the strip. Infinity means nobody
// measured one (a Tray with no bar around it), which shows everything; a
// negative budget is a strip that is already over-full and shows the toggle
// alone. `maxVisible` is the user's own ceiling (`tray.maxVisible`), 0 for
// none: it hides items whether or not they would have fit, which is what
// Bartender and Ice call the always-hidden section.
function fit(total, budget, cell, spacing, maxVisible) {
    if (total <= 0)
        return { inline: 0, hidden: 0 };
    var capped = maxVisible > 0 ? Math.min(total, maxVisible) : total;
    if (!(cell > 0) || !isFinite(budget))
        return { inline: capped, hidden: total - capped };
    var toggle = capped < total ? cell + spacing : 0;
    if (extent(capped, cell, spacing) + toggle <= budget)
        return { inline: capped, hidden: total - capped };
    // Out of room, so the toggle is certain: it takes its own cell off the
    // top and whatever is left is shared out in whole cells, each carrying
    // the gap that precedes the next one.
    var n = Math.max(0, Math.min(capped, Math.floor((budget - cell) / (cell + spacing))));
    return { inline: n, hidden: total - n };
}

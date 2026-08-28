.pragma library

// Whether the tray fits on the strip at all. Pure, so the answer is
// checkable head-on, the same split layout.js and panels.js already take.
//
// All or nothing, by design (owner, 2026-08-28): the strip either carries
// the whole tray or it carries one toggle and the second bar
// (Surfaces/Bar/TrayOverflow.qml) carries every icon. A partial split leaves
// one tray reading across two surfaces, and the cut moves under the user
// whenever anything else on the bar resizes.
//
// Every tray cell is one icon in the bar's own square slot, so a single
// extent describes all of them and the question is arithmetic rather than a
// per-cell measurement: n cells cost n * cell + (n - 1) * spacing.

function extent(n, cell, spacing) {
    return n <= 0 ? 0 : n * cell + (n - 1) * spacing;
}

// `budget` is the room the rail has along the strip. Infinity means nobody
// measured one (a Tray with no bar around it), which shows everything.
// `maxVisible` is the user's own ceiling (`tray.maxVisible`), 0 for none:
// more items than that and the strip hands the lot over whether or not they
// would have fit, which is what Bartender and Ice call the always-hidden
// section.
function fit(total, budget, cell, spacing, maxVisible) {
    if (total <= 0)
        return { inline: 0, hidden: 0 };
    var capped = maxVisible > 0 && total > maxVisible;
    if (!capped && (!(cell > 0) || !isFinite(budget) || extent(total, cell, spacing) <= budget))
        return { inline: total, hidden: 0 };
    return { inline: 0, hidden: total };
}

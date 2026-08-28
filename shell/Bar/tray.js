.pragma library

// Where the tray lives: on the strip, or in the second bar
// (Surfaces/Bar/TrayOverflow.qml). Pure, so the answer is checkable head-on,
// the same split layout.js and panels.js already take.
//
// All or nothing (owner, 2026-08-28): the strip either carries the whole
// tray or it carries one toggle and the second bar carries every icon. A
// partial split leaves one tray reading across two surfaces, and the cut
// moves under the user whenever anything else on the bar resizes.
//
// `maxVisible` (`tray.maxVisible`) is the most icons the strip will carry:
//
//   0   the default, and none: the tray always lives in the second bar,
//       whatever room the strip has (owner, 2026-08-28: the dots are the
//       tray's place on the bar, not a state it falls into).
//   -1  as many as fit, which is the whole tray or none of it.
//   N   up to N, and room still has the last word: more than N icons, or
//       too little strip for the ones there are, and the tray moves.
//
// Every tray cell is one icon in the bar's own square slot, so a single
// extent describes all of them and the room question is arithmetic rather
// than a per-cell measurement: n cells cost n * cell + (n - 1) * spacing.

function extent(n, cell, spacing) {
    return n <= 0 ? 0 : n * cell + (n - 1) * spacing;
}

// Whether the answer depends on a measured strip at all. A ceiling has
// already decided for a tray that is over it (and for the default, which is
// over every ceiling), so the rail can draw the toggle without waiting for a
// bar to measure itself. Only the room question needs a real budget.
function needsRoom(total, maxVisible) {
    if (total <= 0)
        return false;
    if (maxVisible === 0)
        return false;
    return !(maxVisible > 0 && total > maxVisible);
}

// `budget` is the room the rail has along the strip; Infinity means nobody
// measured one, which cannot make the tray move on its own.
function fit(total, budget, cell, spacing, maxVisible) {
    if (total <= 0)
        return { inline: 0, hidden: 0 };
    if (!needsRoom(total, maxVisible))
        return { inline: 0, hidden: total };
    if (!(cell > 0) || !isFinite(budget) || extent(total, cell, spacing) <= budget)
        return { inline: total, hidden: 0 };
    return { inline: 0, hidden: total };
}

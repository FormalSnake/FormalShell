import QtQuick
import qs.Core

// The content lockup inside a bar cell: an icon and its label, laid out
// along the strip. On a horizontal bar that is a row, on a vertical one a
// column, and the glyphs stand up either way, which is the whole reason
// this exists rather than a bare `Row`: a readout on its side beside an
// upright icon is two orientations fighting, and `84%` turned 90 degrees
// is a puzzle rather than a value.
//
// It finds its own cell by walking up rather than being handed one, so a
// widget writes `CellRow { ... }` and nothing else; a lockup outside any
// cell (nothing does this today) stays a row. Reactive to reparenting,
// since each `parent` read is a dependency.
Rail {
    id: root

    readonly property Item cell: {
        var item = root.parent;
        while (item && item.contentAcross === undefined)
            item = item.parent;
        return item;
    }

    vertical: root.cell ? root.cell.vertical : false

    // Centred in the content box on both axes. The box is the measurement's
    // own size along the lockup, so the centring only ever does anything
    // across it (a cell floored at `controlHeight`, a cell given an explicit
    // height by the bar's region delegate).
    anchors.centerIn: parent

    spacing: Theme.space.xxs
}

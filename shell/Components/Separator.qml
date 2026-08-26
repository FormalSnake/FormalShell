import QtQuick
import qs.Core

// A seam (DESIGN.md §2, the separation ladder in §1): a 1px `border` rule
// between two groups that space alone cannot keep apart. Rung 4 of five, and
// the last one before a card, so reaching for it is a claim that `sectionGap`
// and a `SectionLabel` were both tried and neither was enough.
//
// Horizontal by default. `vertical: true` turns it into a column seam, which
// is the split-route and two-column-ledger case; the two orientations are one
// component because a caller picking a rule should not also have to decide
// which of two names draws it.
//
// `inset` pulls both ends in by that much, for a rule that separates rows
// inside a padded list rather than one that spans a whole surface: a seam
// that runs to the card's own border reads as a division of the card, a seam
// inset to the row text reads as a division of the rows. Full-bleed is the
// default because that is the commoner case (a footer, a header, the
// ledger's own split).
Rectangle {
    id: root

    property bool vertical: false
    property real inset: 0

    implicitWidth: root.vertical ? Theme.borderWidth : 0
    implicitHeight: root.vertical ? 0 : Theme.borderWidth

    width: root.vertical ? Theme.borderWidth : undefined
    height: root.vertical ? undefined : Theme.borderWidth

    anchors.leftMargin: root.vertical ? 0 : root.inset
    anchors.rightMargin: root.vertical ? 0 : root.inset
    anchors.topMargin: root.vertical ? root.inset : 0
    anchors.bottomMargin: root.vertical ? root.inset : 0

    color: Theme.color.border
}

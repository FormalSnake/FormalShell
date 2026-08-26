import QtQuick
import qs.Core

// The value beside (or under) a bar cell's icon: `84%`, `22°`, `us`, a
// pending count, a `NO ADAPTER` state. One component rather than a Text per
// widget because a vertical bar makes the same demand of every one of them.
//
// A vertical strip is a fixed width (`space.barCellWidth`) and the label
// stacks under the icon rather than sitting beside it, so a label wider
// than the strip has nowhere to run. It wraps at word boundaries into that
// width first, which is what turns `NO ADAPTER` into two upright lines
// instead of a line lying on its side, and hides only when a single word
// still does not fit: the icon above it says which cell this is, and the
// tooltip carries the words. On a horizontal bar this is a plain Text and
// neither the wrap nor the gate ever engages.
//
// `meta` is the band-2 variant (DESIGN.md §2.3), the section-label look for
// the honest unavailable states, since SectionLabel itself is a panel
// component and knows nothing about a strip's width.
Text {
    id: root

    property bool meta: false

    readonly property Item cell: {
        var item = root.parent;
        while (item && item.contentAcross === undefined)
            item = item.parent;
        return item;
    }

    readonly property bool _vertical: root.cell !== null && root.cell.vertical

    // `contentWidth` is the widest line the wrap actually produced, so this
    // asks whether the longest word fits rather than whether the whole
    // string did.
    readonly property bool _fits: !root._vertical
        || root.contentWidth <= root.cell.contentAcross + 0.5

    // `text !== ""` is the caller's own gate (an empty label is a widget
    // saying it has no value yet) and stays the outer term, so a widget
    // that hides its label keeps hiding it.
    visible: root.text !== "" && root._fits

    width: root._vertical ? root.cell.contentAcross : root.implicitWidth
    wrapMode: root._vertical ? Text.WordWrap : Text.NoWrap
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    color: root.cell
        ? (root.meta ? root.cell.dimForeground : root.cell.foreground)
        : Theme.color.foreground
    font.family: root.meta ? Theme.fontFamilySans : Theme.fontFamilyMono
    font.pixelSize: root.meta ? Theme.fontSize.caption : Theme.fontSize.body
    font.weight: Theme.weight.medium
    font.capitalization: root.meta ? Font.AllUppercase : Font.MixedCase
    font.letterSpacing: root.meta ? Theme.letterSpacing.meta : 0
}

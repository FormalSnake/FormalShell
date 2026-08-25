import QtQuick
import qs.Core

// shadcn's section label (DESIGN.md §2): `caption`, `medium`,
// `mutedForeground`, uppercase, tracked by `letterSpacing.meta`. `count`
// renders as a trailing ` (3)` when it is zero or more; a negative count
// draws nothing.
//
// An Item around the Text rather than a bare Text so `text` stays the
// caller's own string while the paint target renders it plus the count.
// Everything else a caller sets on a Text forwards through by alias, and the
// implicit size tracks the label's, so this measures like the plain Text it
// replaces (Cell's own content measurement included).
Item {
    id: root

    property string text: ""
    property int count: -1
    property alias color: label.color
    property alias elide: label.elide
    property alias horizontalAlignment: label.horizontalAlignment
    property alias font: label.font
    property alias wrapMode: label.wrapMode

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    Text {
        id: label
        anchors.fill: parent
        color: Theme.color.mutedForeground
        font.family: Theme.fontFamilySans
        font.pixelSize: Theme.fontSize.caption
        font.weight: Theme.weight.medium
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Theme.letterSpacing.meta
        text: root.count >= 0 ? root.text + " (" + root.count + ")" : root.text
    }
}

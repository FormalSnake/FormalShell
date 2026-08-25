import QtQuick
import qs.Core

// MetaLabel's sibling for a clickable cell's own primary label — DND, CLEAR
// ALL, a power profile's name — when that label IS the content (band 1,
// DESIGN.md §1.4) rather than a caption naming it (band 2). Same uppercase
// tracking convention as MetaLabel (`Font.AllUppercase` +
// `Theme.letterSpacing.meta`), but body-sized and colored by the caller
// (usually a Cell's own `foreground`, which already carries hover/selection
// inversion) instead of MetaLabel's fixed caption size and `mutedForeground`,
// which would wrongly shrink and dim these.
Text {
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize.body
    font.capitalization: Font.AllUppercase
    font.letterSpacing: Theme.letterSpacing.meta
}

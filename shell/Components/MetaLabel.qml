import QtQuick
import qs.Core

// DESIGN.md's meta-row convention: a tiny uppercase dimmed label — widget
// names, breadcrumbs, states like "BAT / 87%". The one place that
// convention is encoded so every surface's meta rows read identically.
Text {
    id: root

    color: Theme.color.foregroundDim
    font.family: Theme.font.family
    font.pixelSize: Theme.fontSize.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: Theme.letterSpacing.meta
}

import QtQuick
import qs.Core

// DESIGN.md's meta-row convention: a tiny uppercase dimmed label — widget
// names, breadcrumbs, states like "BAT / 87%". The one place that
// convention is encoded so every surface's meta rows read identically.
//
// Wrapped in an Item rather than a bare Text (M19 Task 3, DESIGN.md §2 item
// 10): a section header ends in a trailing colon appended at render time
// only — `text` stays the raw caller-supplied string, never mutated, while
// `label` (the actual paint target) renders `text` plus the colon. Every
// other Text-ism callers already rely on (`color`, `elide`,
// `horizontalAlignment`, the whole `font` group, `wrapMode`) forwards
// through via alias, and `implicitWidth`/`implicitHeight` track `label`'s
// own so this stays a drop-in replacement for the plain-Text version at
// every existing call site (Cell's own content measurement included).
Item {
    id: root

    property string text: ""
    property bool colon: false
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
        color: Theme.color.foregroundDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize.caption
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Theme.letterSpacing.meta
        text: root.text + (root.colon ? ":" : "")
    }
}

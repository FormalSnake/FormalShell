import QtQuick
import qs.Core

// The card title-bar band (DESIGN.md §2 item 9, M19 Task 3): every floating
// card's opening row — an uppercase meta label with the trailing colon at
// the left, an optional right-side slot for meta text or bare-label
// actions, one shared rule under the whole band. Built on Cell, so it
// inherits the shared-rule contract for free (draws its own bottom+right
// rule; a frame's own content erasers paper over the rest, same as every
// other row — see Panel.qml's titleCell, the band this replaces).
//
// Right-side actions are meant to be bare labels (MetaLabel/ActionLabel
// text plus a MouseArea), never full Cell chrome — DESIGN's §1.1
// ink-promotion amendment governs their hover, not the fill-alpha model
// this Cell itself still carries for its own idle/selected states.
Cell {
    id: root

    property string title: ""
    default property alias actions: rightRow.data

    MetaLabel {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        colon: true
    }

    Row {
        id: rightRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.lg
    }
}

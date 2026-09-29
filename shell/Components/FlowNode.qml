import QtQuick
import qs.Core

// One node of the power diagram: an icon over a caption, a mono value and a
// dim detail line. Flat, no box (DESIGN.md §1: a block that only reports a
// value does not get a resting fill and border). An empty `value` drops its
// line rather than printing a placeholder; the icon stays first, so the
// links drawn against `iconCentreY` line up across nodes whatever else is
// missing.
Column {
    id: root

    property string icon: ""
    property string caption: ""
    property string value: ""
    property string detail: ""
    property bool dim: false

    readonly property real iconCentreY: glyph.height / 2
    readonly property real iconSize: glyph.size

    spacing: Theme.space.xxs

    Icon {
        id: glyph
        anchors.horizontalCenter: parent.horizontalCenter
        name: root.icon
        size: Theme.fontSize.heading
        color: root.dim ? Theme.color.mutedForeground : Theme.color.foreground
    }

    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.caption
        color: Theme.color.mutedForeground
        font.family: Theme.fontFamilySans
        font.pixelSize: Theme.fontSize.caption
    }

    Text {
        visible: root.value !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.value
        color: Theme.color.foreground
        font.family: Theme.fontFamilyMono
        font.pixelSize: Theme.fontSize.body
    }

    Text {
        visible: root.detail !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.detail
        color: Theme.color.mutedForeground
        font.family: Theme.fontFamilySans
        font.pixelSize: Theme.fontSize.caption
    }
}

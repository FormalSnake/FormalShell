import QtQuick
import qs.Core
import qs.Components

// The media panel's menu trigger: a chip carrying an icon, what is picked and
// a chevron, `selected` while its menu is open. The label elides rather than
// pushing the chip past `maxWidth`, so two triggers share one line.
Cell {
    id: root

    property string icon: ""
    property string label: ""
    property bool open: false
    property real maxWidth: Infinity

    chip: true
    radius: Theme.radiusSm
    interactive: true
    selected: root.open

    readonly property real _chrome: leadIcon.width + chevron.width + row.spacing * 2 + Theme.space.controlPaddingX * 2

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xs

        Icon {
            id: leadIcon
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            size: Theme.fontSize.bodySmall
            color: root.foreground
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(0, root.maxWidth - root._chrome))
            text: root.label
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.foreground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.bodySmall
            font.weight: Theme.weight.medium
        }

        Icon {
            id: chevron
            anchors.verticalCenter: parent.verticalCenter
            name: root.open ? "chevron-up" : "chevron-down"
            size: Theme.fontSize.caption
            color: root.dimForeground
        }
    }
}

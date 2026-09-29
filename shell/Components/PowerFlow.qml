import QtQuick
import qs.Core

// Where the power goes (Power/flow.js builds `flow`): the adapter, the
// laptop and the battery in a row with a link between each, and under the
// laptop a trunk with one branch per USB-C port. A link shows a moving
// chevron only for a hop power really crosses; a port that supplies nothing
// keeps a plain rule. The caller owns the honest empty state: this draws
// whatever `flow` holds and assumes `flow.available`.
//
// Every figure is a string the model already decided on, so a reading the
// kernel does not give never reaches a Text as a number.
Column {
    id: root

    property var flow: null
    property bool animate: true

    readonly property real _col: root.width / 3
    readonly property real _branch: Theme.space.huge + Theme.space.xxl
    readonly property real _gap: Theme.space.iconGap

    spacing: Theme.space.rowGap

    Item {
        width: root.width
        height: laptopNode.height

        FlowNode {
            id: adapterNode
            x: 0
            width: root._col
            icon: root.flow ? root.flow.adapter.icon : "plug"
            caption: root.flow ? root.flow.adapter.caption : ""
            value: root.flow ? root.flow.adapter.value : ""
            detail: root.flow ? root.flow.adapter.detail : ""
            dim: root.flow ? !root.flow.adapter.online : true
        }

        FlowNode {
            id: laptopNode
            x: root._col
            width: root._col
            icon: root.flow ? root.flow.laptop.icon : "laptop"
            caption: root.flow ? root.flow.laptop.caption : ""
            value: root.flow ? root.flow.laptop.value : ""
            detail: root.flow ? root.flow.laptop.detail : ""
        }

        FlowNode {
            id: batteryNode
            x: root._col * 2
            width: root._col
            icon: root.flow ? root.flow.battery.icon : "battery"
            caption: root.flow ? root.flow.battery.caption : ""
            value: root.flow ? root.flow.battery.value : ""
            detail: root.flow ? root.flow.battery.detail : ""
            dim: root.flow ? !root.flow.battery.present : true
        }

        FlowLink {
            x: root._col / 2 + adapterNode.iconSize / 2 + root._gap
            width: root._col - adapterNode.iconSize - root._gap * 2
            y: adapterNode.iconCentreY - height / 2
            animate: root.animate
            direction: root.flow && root.flow.links.adapter ? 1 : 0
        }

        FlowLink {
            x: root._col * 1.5 + laptopNode.iconSize / 2 + root._gap
            width: root._col - laptopNode.iconSize - root._gap * 2
            y: laptopNode.iconCentreY - height / 2
            animate: root.animate
            direction: root.flow && root.flow.links.battery === "in" ? 1
                : root.flow && root.flow.links.battery === "out" ? -1 : 0
        }
    }

    Repeater {
        model: root.flow ? root.flow.ports : []

        delegate: Item {
            id: portRow

            required property var modelData
            required property int index
            readonly property bool last: portRow.index === (root.flow ? root.flow.ports.length : 0) - 1
            readonly property real trunkX: root.width / 2

            width: root.width
            height: portText.height + Theme.space.rowGap * 2

            Text {
                anchors.left: parent.left
                anchors.right: trunk.left
                anchors.rightMargin: root._gap
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: portRow.modelData.name
                color: Theme.color.mutedForeground
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.caption
            }

            Separator {
                id: trunk
                vertical: true
                x: portRow.trunkX
                y: 0
                height: portRow.last ? portRow.height / 2 : portRow.height
            }

            FlowLink {
                id: branch
                x: portRow.trunkX
                width: root._branch
                y: portRow.height / 2 - height / 2
                animate: root.animate
                direction: portRow.modelData.powering ? 1 : portRow.modelData.supplying ? -1 : 0
            }

            Column {
                id: portText
                x: branch.x + branch.width + root._gap
                width: root.width - x
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    visible: text !== ""
                    width: parent.width
                    elide: Text.ElideRight
                    text: portRow.modelData.label
                    color: Theme.color.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.body
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: portRow.modelData.detail
                    color: Theme.color.mutedForeground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.caption
                }
            }
        }
    }
}

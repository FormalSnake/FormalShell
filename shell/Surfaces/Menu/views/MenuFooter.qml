import QtQuick
import qs.Core as Core
import qs.Components

// The launcher's footer band (M72 T4), Raycast's: where you are on the
// left, the level's icon and name; what Enter does on the right, as a
// `Button` carrying its key, then the legend for the other keys that apply.
// Menu/actions.js owns the wording of both.
//
// The verb is the one thing here that answers a click, doing exactly what
// Enter does. It goes when the cursor sits on something that cannot be
// activated, and the band keeps its height either way: it is a
// `controlHeight` row whether a button is in it or not, so the card does
// not change size under the cursor.
Item {
    id: root

    property string levelIcon: ""
    property string levelName: ""
    property var primary: null
    property var hints: []

    signal primaryActivated

    implicitHeight: Core.Theme.space.controlHeight

    Row {
        id: where
        anchors.left: parent.left
        anchors.leftMargin: Core.Theme.space.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        spacing: Core.Theme.space.iconGap

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.levelIcon !== ""
            name: root.levelIcon !== "" ? root.levelIcon : "circle-help"
            size: Core.Theme.fontSize.body
            color: Core.Theme.color.mutedForeground
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(0, root.width - actions.width
                - Core.Theme.space.controlPaddingX * 2 - Core.Theme.fontSize.body - Core.Theme.space.iconGap))
            elide: Text.ElideRight
            text: root.levelName
            color: Core.Theme.color.mutedForeground
            font.family: Core.Theme.fontFamilySans
            font.pixelSize: Core.Theme.fontSize.bodySmall
        }
    }

    Row {
        id: actions
        anchors.right: parent.right
        anchors.rightMargin: Core.Theme.space.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        spacing: Core.Theme.space.md

        Button {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!root.primary
            variant: "ghost"
            text: root.primary ? root.primary.label : ""
            shortcut: root.primary ? root.primary.key : ""
            onClicked: root.primaryActivated()
        }

        // The legend: a key and what it does, never a control. Keys are
        // values, so mono; the verbs are words.
        Repeater {
            model: root.hints

            delegate: Row {
                required property var modelData

                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                spacing: Core.Theme.space.xs

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.key
                    color: Core.Theme.color.mutedForeground
                    font.family: Core.Theme.fontFamilyMono
                    font.pixelSize: Core.Theme.fontSize.caption
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: Core.Theme.color.mutedForeground
                    font.family: Core.Theme.fontFamilySans
                    font.pixelSize: Core.Theme.fontSize.caption
                }
            }
        }
    }
}

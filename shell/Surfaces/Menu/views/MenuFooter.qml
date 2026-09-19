import QtQuick
import qs.Core as Core
import qs.Components

// The launcher's footer band (M72 T4), Raycast's: where you are on the
// left, the level's icon and name; what Enter does on the right, as a
// `Button` followed by its key's cap, then each other key that applies as
// its verb and its caps.
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

    // The verb, then each legend entry, `xxl` apart; inside an entry the
    // words sit `sm` off their caps, so a key is read with the verb it
    // belongs to rather than with the next one along. The button's own
    // padding is the gap before its cap.
    Row {
        id: actions
        anchors.right: parent.right
        anchors.rightMargin: Core.Theme.space.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        spacing: Core.Theme.space.xxl

        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!root.primary

            Button {
                anchors.verticalCenter: parent.verticalCenter
                variant: "ghost"
                paddingX: Core.Theme.space.lg
                text: root.primary ? root.primary.label : ""
                onClicked: root.primaryActivated()
            }

            Chord {
                anchors.verticalCenter: parent.verticalCenter
                keys: root.primary ? root.primary.keys : []
            }
        }

        // The legend: what a key does, never a control. The verb is words in
        // the muted ink, its keys on their caps after it.
        Repeater {
            model: root.hints

            delegate: Row {
                required property var modelData

                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                spacing: Core.Theme.space.sm

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: Core.Theme.color.mutedForeground
                    font.family: Core.Theme.fontFamilySans
                    font.pixelSize: Core.Theme.fontSize.bodySmall
                }

                Chord {
                    anchors.verticalCenter: parent.verticalCenter
                    keys: modelData.keys
                }
            }
        }
    }
}

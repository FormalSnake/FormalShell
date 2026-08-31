import QtQuick
import qs.Core

// shadcn's text field (DESIGN.md §2): an `input` border at `radiusMd`,
// `controlHeight` tall, the ring while it holds focus, a `destructive`
// border plus a caption under it while `error`.
//
// `editing` is what a surrounding KeyCatcher blocks on: while the field has
// focus the keys are the field's, not the panel's.
Item {
    id: root

    property alias text: input.text
    property alias echoMode: input.echoMode
    readonly property alias editing: input.activeFocus
    property string placeholder: ""
    property bool error: false
    property string errorText: ""

    signal accepted()
    // Fired on every key reaching the field, before the field's own
    // handling and without accepting the event, so nothing here swallows a
    // keystroke the field would otherwise take. The lock screen's idle-wake
    // rides on it.
    signal activity()

    function forceFocus() {
        input.forceActiveFocus();
    }

    readonly property bool _showsError: root.error && root.errorText !== ""

    implicitWidth: input.implicitWidth + Theme.space.controlPaddingX * 2
    implicitHeight: frame.height + (root._showsError ? Theme.space.xs + errorLabel.implicitHeight : 0)

    // The halo fades in and out with focus (M51 Task 5) rather than popping:
    // `visible` still drops it at 0 so it costs nothing at rest, and the
    // opacity Behavior is what gives the fade somewhere to happen before
    // that.
    Rectangle {
        id: ring
        anchors.fill: frame
        anchors.margins: -Theme.ringWidth
        visible: ring.opacity > 0
        radius: Theme.radiusMd + Theme.ringWidth
        color: Theme.color.ring
        opacity: input.activeFocus ? Theme.ringAlpha : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easingInOut }
        }
    }

    Rectangle {
        id: frame
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Theme.space.controlHeight
        radius: Theme.radiusMd
        color: "transparent"
        border.width: Theme.borderWidth
        // Focus, blur and error all crossfade the border colour on the same
        // `fast` Behavior: `fast` is short enough (100ms) that a validation
        // error still reads as landing instantly, so error gets no special
        // case that would make it look like a different kind of change.
        border.color: root.error
            ? Theme.color.destructive
            : input.activeFocus
                ? Theme.color.ring
                : Theme.color.input
        Behavior on border.color {
            ColorAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easingInOut }
        }

        Text {
            anchors.fill: input
            visible: input.text === ""
            verticalAlignment: Text.AlignVCenter
            text: root.placeholder
            color: Theme.color.mutedForeground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.body
            elide: Text.ElideRight
        }

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: Theme.space.controlPaddingX
            anchors.rightMargin: Theme.space.controlPaddingX
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.color.foreground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.body
            selectByMouse: true
            selectionColor: Theme.color.primary
            selectedTextColor: Theme.color.primaryForeground
            Keys.onPressed: event => root.activity()
            onAccepted: root.accepted()
        }
    }

    Text {
        id: errorLabel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: frame.bottom
        anchors.topMargin: Theme.space.xs
        visible: root._showsError
        text: root.errorText
        color: Theme.color.destructive
        font.family: Theme.fontFamilySans
        font.pixelSize: Theme.fontSize.caption
        wrapMode: Text.WordWrap
    }
}

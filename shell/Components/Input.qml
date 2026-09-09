import QtQuick
import qs.Core
import "cursor.js" as Cursor

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

    // True one tick past creation, so the field's first layout is not an
    // animation: a Behavior fires on any write, including the one a fresh
    // binding makes, and a card built with its caption already up would
    // otherwise grow into place as it appeared.
    property bool _settled: false
    // Set when a framed surface above (Panel's content column, the polkit
    // card) animates its own height: the caption's space then opens on that
    // frame's clock instead, since two clocks on one size change leave the
    // frame trailing its own content. Resolved a tick late for the reason
    // cursor.js gives.
    property bool _morphOwned: false

    // A Timer rather than Component.onCompleted: callers of this field
    // declare completion handlers of their own on it (NetworkPanel's two
    // wifi fields both do), and this arming must not depend on how QML
    // resolves two handlers for one signal on one object.
    Timer {
        interval: 0
        running: true
        onTriggered: {
            root._morphOwned = Cursor.ownedAbove(root, "ownsSizeMorph");
            root._settled = true;
        }
    }

    implicitWidth: input.implicitWidth + Theme.space.controlPaddingX * 2
    implicitHeight: frame.height + (root._showsError ? Theme.space.xs + errorLabel.implicitHeight : 0)

    // The caption's height arrives as a size change on a control already on
    // screen (M53 D2), so the field grows into it rather than jumping a row
    // taller under whatever sits below it.
    Behavior on implicitHeight {
        enabled: root._settled && root.visible && !root._morphOwned
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easingInOut }
    }

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
        // The caption crosses in and out on the same clock the border does
        // (M53 D3), so an error lands as one change rather than a word
        // appearing over a colour still on its way.
        visible: errorLabel.opacity > 0
        opacity: root._showsError ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easingInOut }
        }
        text: root.errorText
        color: Theme.color.destructive
        font.family: Theme.fontFamilySans
        font.pixelSize: Theme.fontSize.caption
        wrapMode: Text.WordWrap
    }
}

import QtQuick
import qs.Core as Core
import qs.Components

// The split route's right half (M30, M43 D4): the cursor row's full
// content in an inner `Card`, a `sm` gutter off the list.
// This is the launcher spending its one card (DESIGN.md §1's ladder, rung
// 5, owner 2026-08-26): the surface's own frame, and inside it exactly one
// block that outranks the rest. The left half is flat `MenuRow`s and this
// half is the card, so the pane reads as the thing the list is pointing at.
// What the rule rules out is a second frame INSIDE this one, which is what
// an image row used to get.
Card {
    id: root

    property string previewKind: ""
    property string previewTime: ""
    property bool isText: false
    property string text: ""
    property bool isImage: false
    property string imageSource: ""
    property real pixelRatio: 1

    Row {
        id: previewHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.space.sm

        SectionLabel {
            visible: root.previewKind !== ""
            text: root.previewKind
        }

        Text {
            visible: root.previewTime !== ""
            text: root.previewTime
            color: Core.Theme.color.mutedForeground
            font.family: Core.Theme.fontFamilyMono
            font.pixelSize: Core.Theme.fontSize.caption
        }
    }

    Text {
        id: previewText
        anchors.top: previewHeader.bottom
        anchors.topMargin: Core.Theme.space.rowGap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // The two slots share one frame, so the cursor stepping from a text
        // capture to an image one is a content swap and crossfades (M53
        // D3).
        opacity: root.isText ? 1 : 0
        visible: previewText.opacity > 0
        Behavior on opacity {
            Anim { kind: "effects" }
        }
        clip: true
        text: root.text
        // A clipboard capture reaches this pane raw, so the preview has to
        // show the bytes that will be pasted rather than let AutoText parse
        // copied markup as a rich-text document.
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        color: Core.Theme.color.foreground
        font.family: Core.Theme.fontFamilyMono
        font.pixelSize: Core.Theme.fontSize.body
    }

    // True-color (menu thumbnails are never dithered) full preview of the
    // cursor row's capture, decode capped at the slot's own size for the
    // picker grid's reason. Bare: no well, no frame, no outline. The pane
    // around it is already the one card this surface gets, and a border
    // inside that is the nesting the rule forbids. It fits rather than
    // fills, so the pane's own ground shows around it, which is what a
    // letterboxed capture is supposed to sit on.
    Image {
        id: previewImage
        anchors.top: previewHeader.bottom
        anchors.topMargin: Core.Theme.space.rowGap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // The other half of the swap above.
        opacity: root.isImage ? 1 : 0
        visible: previewImage.opacity > 0
        Behavior on opacity {
            Anim { kind: "effects" }
        }
        source: root.imageSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        sourceSize.width: previewImage.width * root.pixelRatio
        sourceSize.height: previewImage.height * root.pixelRatio
    }
}

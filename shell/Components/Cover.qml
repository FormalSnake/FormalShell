import QtQuick
import Quickshell.Widgets
import qs.Core

// Content imagery with an edge of its own (DESIGN.md §1's separation ladder):
// a `muted` well, a 1px `border`, and the picture clipped to the same rounded
// shape. Album art in the bar and in the media panel, a notification's app
// icon. An outline on a picture is not a nested card, and this is the one
// component that draws it, so every cover slot in the shell rounds the same
// way.
//
// `Quickshell.Widgets.ClippingRectangle` rather than `clip: true`: Qt's clip
// is rectangular, so a rounded frame over a square picture leaves the
// picture's own corners poking past its border. The clipper costs a
// ShaderEffect per instance (its own docs say so), which is why this is a
// component of its own rather than a flag on `Picture`: an icon that wants no
// edge stays a plain Image and pays nothing.
//
// The radius comes off `Theme.coverRadius(extent)`, a quarter of the slot's
// shorter side capped at `radiusSm`, so the bar's 17px cover is slightly
// rounded rather than most of the way to a circle (owner, 2026-08-26) and a
// 96px panel cover still lands on the ladder. Square under `theme.radius: 0`.
//
// `overlay` is the slot for something drawn over the still: the media panel's
// animated Apple Music cover, which layers on top of the static art and falls
// back to it for every path it doesn't cover. It sits inside the same clip.
ClippingRectangle {
    id: root

    property alias source: picture.source
    property alias fillMode: picture.fillMode
    property alias sourceSize: picture.sourceSize
    property alias cache: picture.cache
    property alias asynchronous: picture.asynchronous
    readonly property alias status: picture.status

    property alias overlay: overlayItem.data

    color: Theme.color.muted
    radius: Theme.coverRadius(Math.min(root.width, root.height))
    border.width: Theme.borderWidth
    border.color: Theme.color.border
    // The border is all the inset the picture gets: a cover fills its frame
    // rather than floating in it.
    contentInsideBorder: true

    // The frame is chrome and never dithers; the picture inside it is content
    // and goes through `Picture`'s retro pass like every other image.
    Picture {
        id: picture
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
    }

    Item {
        id: overlayItem
        anchors.fill: parent
    }
}

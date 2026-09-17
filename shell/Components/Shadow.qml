import QtQuick
import QtQuick.Effects
import qs.Core

// The floating surface's shadow (DESIGN.md §1 "Depth", `theme.depth`): a
// soft black cast a few pixels down from a silhouette, and nothing inside
// the silhouette itself. The silhouette is whatever the consumer puts in the
// default slot, drawn black at this item's own size (a rounded rect for a
// Card, a Shoulders for a drawer). It is never shown: it renders into one
// layer that serves twice, as the shadow's source and, inverted, as its
// mask, so the cast is cut at the surface's own edge and a translucent card
// over it keeps the blurred desktop it shows rather than gaining a black
// backing. Sits at `z: -1` inside the surface, which puts it under the
// surface's own fill, and reaches `Theme.shadow.extent` past every side.
Item {
    id: root

    default property alias silhouette: slot.data
    property bool shown: true

    readonly property real _extent: Theme.shadow.extent

    visible: Theme.depth && root.shown

    Item {
        id: proxy
        visible: false
        layer.enabled: root.visible
        x: -root._extent
        y: -root._extent
        width: root.width + root._extent * 2
        height: root.height + root._extent * 2

        Item {
            id: slot
            x: root._extent
            y: root._extent
            width: root.width
            height: root.height
        }
    }

    MultiEffect {
        anchors.fill: proxy
        source: proxy
        // The layer above is already padded by `extent`, so the effect item
        // is the layer's own size and the blur has its room without a resize
        // on every frame the silhouette changes.
        autoPaddingEnabled: false
        shadowEnabled: true
        shadowColor: "black"
        shadowOpacity: Theme.shadowAlpha
        blurMax: Theme.shadow.blurMax
        shadowBlur: Theme.shadow.blur
        shadowVerticalOffset: Theme.shadow.offset
        maskEnabled: true
        maskSource: proxy
        maskInverted: true
        maskThresholdMin: 0.5
    }
}

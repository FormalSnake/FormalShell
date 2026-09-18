import QtQuick
import QtQuick.Effects

// The glow a band's ink carries (M63 O6): the table's `inkShadow` layer
// list drawn as CSS draws a text-shadow, one `MultiEffect` per layer behind
// the glyphs, first layer on top. wingpanel's contrast on a transparent
// panel is exactly this pair of shadows, and `Text.Raised` can only offset
// by a pixel with no blur under it.
//
// The source is drawn BY the effects rather than by itself: a MultiEffect
// renders its source plus the shadow, so the topmost layer carries the
// crisp glyphs and the ones under it carry only their halos. That is also
// the one arrangement Qt supports here. A padded effect writes its own
// `sourceRect` onto a layered source (QGfxSourceProxyME), which rescales
// what that source draws, so a source that still drew itself would come out
// shrunk; the caller hides it instead (`opacity: 0` rather than `visible`,
// which would take an interactive child in the box out of the pointer's
// reach) and leaves `layer.enabled` on, so every layer here samples one
// texture rather than allocating a proxy each.
//
// Both effects therefore have to ask that shared layer for the SAME source
// rect, which is why `blurMax` and `paddingRect` are the list's own maxima
// rather than each layer's. Nothing is instantiated for an empty list, so a
// table declaring no shadow pays nothing at all.
Item {
    id: root

    // The item the glyphs are in, hidden and layered by its owner.
    required property Item source

    // `{ x, y, blur, color }` per layer, resolved (shell/Theme/style.js).
    property var shadows: []

    readonly property bool on: root.shadows.length > 0

    // The blur budget every layer's own `shadowBlur` is a fraction of, and
    // the offset budget on top of it. MultiEffect pads by `blurMax` and adds
    // `paddingRect`, so the two together are what keeps the widest halo off
    // the edge of the texture.
    readonly property int _blurMax: {
        var max = 1;
        for (var i = 0; i < root.shadows.length; i++)
            max = Math.max(max, root.shadows[i].blur);
        return Math.ceil(max);
    }

    readonly property real _reach: {
        var max = 0;
        for (var i = 0; i < root.shadows.length; i++)
            max = Math.max(max, Math.abs(root.shadows[i].x), Math.abs(root.shadows[i].y));
        return Math.ceil(max);
    }

    readonly property rect _padding: Qt.rect(root._reach, root._reach,
        root._reach * 2, root._reach * 2)

    Repeater {
        model: root.shadows

        // Later layers sit lower, the way a CSS shadow list stacks.
        delegate: MultiEffect {
            required property var modelData
            required property int index

            anchors.fill: parent
            z: -index
            source: root.source
            blurMax: root._blurMax
            paddingRect: root._padding
            shadowEnabled: true
            shadowColor: modelData.color
            shadowBlur: Math.min(1, modelData.blur / root._blurMax)
            shadowHorizontalOffset: modelData.x
            shadowVerticalOffset: modelData.y
        }
    }
}

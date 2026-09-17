import QtQuick
import qs.Core

// The floating surface's frame (DESIGN.md §2): the `card` role's box with
// `panelPadding` around its content. Panels, toasts, the launcher and the
// OSD all sit in one of these, and what the frame looks like is the theme's
// answer (shell/Theme/themes/), never this file's.
//
// A consumer states a `state` the role describes (`opaque` on a surface the
// compositor does not blur) or a `role` of its own where the table carries
// one for it (`notification`), and a `radius` where the concentric rule
// asks for one: that is geometry, so it stays the consumer's.
Box {
    id: root

    role: "card"
    padding: Theme.space.panelPadding

    implicitWidth: root._measure(false) + root.padding * 2
    implicitHeight: root._measure(true) + root.padding * 2

    // Each child's own extent, skipping the ones anchored to fill: the slot
    // takes its size from the card, so a fill-anchored child measures at
    // exactly the size this measurement is producing and the binding loops.
    // Same rule, same reason, as Cell.qml's own _measure().
    function _measure(vertical) {
        var max = 0;
        var slot = root.contentItem;
        for (var i = 0; i < slot.children.length; i++) {
            var child = slot.children[i];
            if (child.anchors.fill === slot)
                continue;
            var extent = vertical ? child.height : child.width;
            if (extent > max)
                max = extent;
        }
        return max;
    }
}

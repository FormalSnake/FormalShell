import QtQuick
import qs.Core

// The floating surface's frame (DESIGN.md §2): `card` fill, 1px `border`,
// `radiusXl`, `panelPadding` around the default slot. Panels, toasts, the
// launcher and the OSD all sit in one of these.
Rectangle {
    id: root

    default property alias content: inner.data
    property real padding: Theme.space.panelPadding

    color: Theme.color.card
    radius: Theme.radiusXl
    border.width: Theme.borderWidth
    border.color: Theme.color.border

    implicitWidth: root._measure(false) + root.padding * 2
    implicitHeight: root._measure(true) + root.padding * 2

    // Each child's own extent, skipping the ones anchored to fill: `inner`
    // takes its size from the card, so a fill-anchored child measures at
    // exactly the size this measurement is producing and the binding loops.
    // Same rule, same reason, as Cell.qml's own _measure().
    function _measure(vertical) {
        var max = 0;
        for (var i = 0; i < inner.children.length; i++) {
            var child = inner.children[i];
            if (child.anchors.fill === inner)
                continue;
            var extent = vertical ? child.height : child.width;
            if (extent > max)
                max = extent;
        }
        return max;
    }

    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: root.padding
    }
}

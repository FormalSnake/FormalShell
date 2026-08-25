import QtQuick
import qs.Core

// The wheel seam every scrolling surface shares (M47 D3): declared inside a
// Flickable (the launcher's row list and picker grid, a panel's content
// column, the notification centre, an app view's table), it moves that
// flickable one row per notch and leaves the surface's own keyboard cursor
// where it is.
//
// Ordering is what keeps a slider row working: a child MouseArea that
// accepts the wheel (AudioPanel's stream rails, PanelHero's, the bar's
// audio cell via `Cell.wheeled`) is delivered before this handler, which
// only ever sees the notches nothing else claimed.
WheelHandler {
    id: root

    required property Flickable flickable

    // One notch, one row. The picker's grid passes its own cell height.
    property real step: Theme.space.controlHeight

    // A flickable with nothing to scroll must not consume the event either
    // (`blocking` is true by default, so an enabled handler swallows it
    // whether or not this moved anything).
    enabled: root.flickable && root.flickable.contentHeight > root.flickable.height

    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

    onWheel: event => {
        var flick = root.flickable;
        if (!flick)
            return;
        var max = Math.max(0, flick.contentHeight - flick.height);
        // A touchpad reports the finger's own travel in pixelDelta and a
        // wheel reports notches in angleDelta, 120 units to the notch.
        var delta = event.pixelDelta.y !== 0
            ? event.pixelDelta.y
            : (event.angleDelta.y / 120) * root.step;
        flick.contentY = Math.max(0, Math.min(max, flick.contentY - delta));
    }
}

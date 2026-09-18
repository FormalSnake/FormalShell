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

    // A notch glides rather than jumping a row (M53 D2). On `spatialFast`,
    // so a notch at either end of the list carries the content a few pixels
    // past the bound and back: the flickable only enforces its bounds at the
    // end of its own drag or flick, so a contentY written from here is free
    // to overshoot.
    //
    // A standalone animation on contentY rather than a Behavior, because
    // everything else that moves the view has to be able to end it: a drag
    // or a flick (movementStarted below), and a surface's own keyboard
    // cursor following its current item (`cancel()`). A glide left running
    // under either writes its next frame over the position they just set.
    // `_target` is where the last notch asked to be, so a second notch
    // mid-glide accumulates from that destination instead of from wherever
    // the animation has reached, which is what keeps a held wheel at the
    // wheel's pace.
    property real _target: 0

    // Held in properties: a pointer handler has no default property to
    // parent children to.
    readonly property Anim _glide: Anim {
        id: glide
        target: root.flickable
        property: "contentY"
        kind: "spatialFast"
    }

    function cancel() {
        glide.stop();
    }

    readonly property Connections _movement: Connections {
        target: root.flickable
        function onMovementStarted() { glide.stop(); }
    }

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
        var base = glide.running ? root._target : flick.contentY;
        root._target = Math.max(0, Math.min(max, base - delta));
        glide.stop();
        glide.to = root._target;
        glide.start();
    }
}

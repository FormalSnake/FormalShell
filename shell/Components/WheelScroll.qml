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

    // A notch glides rather than jumping a row (M53 D2). The animated value
    // lives here and is written into the flickable, rather than the
    // flickable carrying a `Behavior on contentY`, because a drag and a
    // flick write that property themselves and neither may be animated
    // behind the finger. `_target` is where the last notch asked to be, so a
    // second notch mid-glide accumulates from that destination instead of
    // from wherever the animation has reached, which is what keeps a held
    // wheel at the wheel's pace.
    property real _target: 0
    property real _glide: 0
    // Set for the one write that resyncs `_glide` with a contentY something
    // else moved, which has to land instantly.
    property bool _sync: false

    Behavior on _glide {
        enabled: !root._sync && root.flickable && !root.flickable.dragging && !root.flickable.flicking
        NumberAnimation {
            id: glideAnimation
            duration: Theme.motion.standard
            easing.type: Theme.motion.easing
        }
    }

    on_GlideChanged: {
        var flick = root.flickable;
        if (flick && !flick.dragging && !flick.flicking)
            flick.contentY = root._glide;
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
        var base = flick.contentY;
        if (glideAnimation.running) {
            base = root._target;
        } else {
            root._sync = true;
            root._glide = flick.contentY;
            root._sync = false;
        }
        root._target = Math.max(0, Math.min(max, base - delta));
        root._glide = root._target;
    }
}

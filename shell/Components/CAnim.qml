import QtQuick
import qs.Core

// The colour half of the primitive (M54 D4): every `Behavior on color`,
// `Behavior on border.color` and palette-token crossfade in the shell.
// One kind, `effectsSlow`, since a colour has no position to overshoot and
// a crossfade shorter than that reads as a flicker rather than a change.
ColorAnimation {
    duration: Theme.motion.effectsSlow
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.motion.curves.effectsSlow
}

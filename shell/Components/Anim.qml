import QtQuick
import qs.Core

// The one animation primitive (DESIGN.md §1 "Motion", M54 D4). A surface
// writes `Behavior on x { Anim {} }` or `Behavior on opacity { Anim { kind:
// "effects" } }` and never a duration or a curve of its own, so the whole
// shell moves on one table (`Theme.motion`).
//
// The property picks the kind, not the surface (M54 D2): `spatialFast`,
// `spatial`, `spatialSlow` for anything with a position or a size (x, y,
// width, height, margins, scale, radius, rotation, an emerge, a morph, a
// cursor), `effectsFast`, `effects`, `effectsSlow` for anything with
// neither (opacity, blur, a progress that only drives alpha; colour takes
// `CAnim`). `emphasized` is the workspace pill, `emphasizedDecel` a toast
// arriving from off screen, `reveal` a full-screen fade.
//
// The spatial curves carry a y control point above 1, so an x or a height
// on one of them passes a few pixels beyond its target and settles back.
// Put a spatial kind on an opacity and Qt clamps the overshoot, which reads
// as the fade stalling just short of the end.
NumberAnimation {
    id: root

    property string kind: "spatial"

    // `emphasizedDecel` is a curve M3 defines without a duration of its
    // own; caelestia runs it on the default spatial clock and so do we.
    readonly property string _clock: root.kind === "emphasizedDecel" ? "spatial" : root.kind

    duration: Theme.motion[root._clock]
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.motion.curves[root.kind]
}

import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// The animation primitive (DESIGN.md §1 "Motion", M54 D4): `kind` resolves
// both halves of a clock, the duration and the curve, so a surface writing
// `Behavior on x { Anim {} }` carries neither. `motion.enabled=false` zeroes
// the duration and the Behavior lands on the same value in one turn.
TestCase {
    id: testCase
    name: "Anim"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component {
        id: animComponent
        Anim {}
    }

    Component {
        id: moverComponent
        QtObject {
            property real value: 0
            Behavior on value {
                Anim {}
            }
        }
    }

    property bool _originalMotionEnabled

    function init() {
        testCase._originalMotionEnabled = Theme.motionEnabled;
    }

    function cleanup() {
        Theme.motionEnabled = testCase._originalMotionEnabled;
    }

    function test_kind_resolves_the_duration_and_the_curve() {
        var anim = createTemporaryObject(animComponent, testCase, { kind: "effects" });
        compare(anim.duration, 200);
        compare(anim.easing.type, Easing.BezierSpline);
        var curve = Theme.motion.curves.effects;
        compare(anim.easing.bezierCurve.length, curve.length);
        for (var i = 0; i < curve.length; i++)
            fuzzyCompare(anim.easing.bezierCurve[i], curve[i], 0.000001);
    }

    function test_default_kind_is_the_spatial_clock() {
        var anim = createTemporaryObject(animComponent, testCase, {});
        compare(anim.kind, "spatial");
        compare(anim.duration, 500);
    }

    // `emphasizedDecel` is a curve without a clock of its own, so it runs on
    // `spatial`'s while carrying its own bezier.
    function test_emphasized_decel_runs_on_the_spatial_clock() {
        var anim = createTemporaryObject(animComponent, testCase, { kind: "emphasizedDecel" });
        compare(anim.duration, Theme.motion.spatial);
        compare(anim.easing.bezierCurve.length, Theme.motion.curves.emphasizedDecel.length);
    }

    function test_behavior_lands_on_the_target_within_the_clock() {
        var mover = createTemporaryObject(moverComponent, testCase, {});
        mover.value = 100;
        verify(mover.value < 100, "the Behavior did not take the change");
        tryCompare(mover, "value", 100, Theme.motion.spatial + 200);
    }

    function test_motion_disabled_lands_at_once() {
        Theme.motionEnabled = false;
        var mover = createTemporaryObject(moverComponent, testCase, {});
        mover.value = 100;
        // Nothing to wait out: motionTokens zeroes every duration, so the
        // zero-length animation is done on the next turn of the loop.
        tryCompare(mover, "value", 100, 100);
    }
}

import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// The velocity deform (DESIGN.md §1 "Motion", M54 D7): a card in travel
// stretches along the direction it is going and compresses across it, and
// the springs carrying the matrix unwind to identity once it stops. With
// motion off the matrix never leaves identity.
TestCase {
    id: testCase
    name: "Deform"
    width: 400
    height: 400
    visible: true
    when: windowShown

    // 50px a frame is ~3700px/s at this rig's frame time, well past the
    // 5px/s dead band and short of the stretch cap.
    property bool driving: false

    Item {
        id: card
        width: 200
        height: 100
    }

    FrameAnimation {
        running: testCase.driving
        onTriggered: card.x += 50
    }

    Component {
        id: deformComponent
        Deform {}
    }

    property bool _originalMotionEnabled

    function init() {
        testCase._originalMotionEnabled = Theme.motionEnabled;
    }

    function cleanup() {
        testCase.driving = false;
        card.x = 0;
        Theme.motionEnabled = testCase._originalMotionEnabled;
    }

    function _identity(m) {
        return m.m11 === 1 && m.m12 === 0 && m.m21 === 0 && m.m22 === 1;
    }

    function test_travel_stretches_along_it_and_compresses_across_it() {
        var deform = createTemporaryObject(deformComponent, testCase,
            { target: card, active: true, edge: "top" });
        verify(testCase._identity(deform.matrix), "a standing card is not at identity");
        testCase.driving = true;
        tryVerify(function () {
            return deform.matrix.m11 > 1 && deform.matrix.m22 < 1;
        }, 2000, "the matrix never stretched along the travel");
    }

    function test_matrix_unwinds_to_identity_once_the_travel_stops() {
        var deform = createTemporaryObject(deformComponent, testCase,
            { target: card, active: true, edge: "top" });
        testCase.driving = true;
        tryVerify(function () {
            return deform.matrix.m11 > 1;
        }, 2000);
        testCase.driving = false;
        tryVerify(function () {
            return testCase._identity(deform.matrix);
        }, 1000, "the springs never settled");
    }

    // M54 D5: the reduced-motion switch is undeformed as well as instant.
    function test_motion_disabled_holds_identity() {
        Theme.motionEnabled = false;
        var deform = createTemporaryObject(deformComponent, testCase,
            { target: card, active: true, edge: "top" });
        testCase.driving = true;
        wait(300);
        verify(testCase._identity(deform.matrix), "the matrix moved with motion off");
    }
}

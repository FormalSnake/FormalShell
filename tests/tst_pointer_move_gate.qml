import QtQuick
import QtTest
import "../shell/Components"

// Interaction guard for shell/Components/PointerMoveGate.qml — the gate that
// stops a re-filtered menu from handing its keyboard cursor to a stationary
// mouse (shell/Surfaces/Menu/Menu.qml's row delegate).
//
// The gate's state machine lives in the QML object rather than a .js library
// (it is one small object with no other logic to share), so these tests
// instantiate the real component the same way tst_cell_geometry.qml
// instantiates the real Cell, and drive movedTo() — the pure decision, taking
// the scene coordinates moved() would have mapped an event into.
TestCase {
    id: testCase
    name: "PointerMoveGate"

    Component {
        id: gateComponent

        PointerMoveGate {}
    }

    function newGate() {
        var gate = createTemporaryObject(gateComponent, testCase);
        verify(gate);
        return gate;
    }

    // The first sample after a keyboard path is the row that slid under the
    // pointer reporting itself, not the pointer arriving.
    function test_not_yet_primed_does_not_select() {
        var gate = newGate();
        compare(gate.movedTo(100, 100), false);
    }

    function test_sub_threshold_jitter_does_not_select() {
        var gate = newGate();
        gate.movedTo(100, 100);
        compare(gate.movedTo(100.5, 100.5), false);
        compare(gate.movedTo(101, 100), false);
    }

    function test_real_move_selects() {
        var gate = newGate();
        gate.movedTo(100, 100);
        compare(gate.movedTo(100, 120), true);
    }

    // A rejected sample must not become the new baseline, or a slow drag
    // would jitter forever without ever crossing the threshold.
    function test_sub_threshold_steps_accumulate_into_a_move() {
        var gate = newGate();
        gate.movedTo(100, 100);
        compare(gate.movedTo(100.6, 100), false);
        compare(gate.movedTo(101.4, 100), true);
    }

    function test_reset_rearms_the_gate() {
        var gate = newGate();
        gate.movedTo(100, 100);
        compare(gate.movedTo(140, 100), true);
        gate.reset();
        // Same coordinates the gate accepted a moment ago: after a reset it
        // has no baseline to have moved away from.
        compare(gate.movedTo(140, 100), false);
        compare(gate.movedTo(160, 100), true);
    }

    function test_allow_stationary_sample_permits_one_stationary_sample() {
        var gate = newGate();
        gate.allowStationarySample();
        compare(gate.movedTo(100, 100), true);
        // Consumed by that sample — the parked pointer gets no second one.
        compare(gate.movedTo(100, 100), false);
    }

    function test_allow_stationary_sample_discards_the_previous_baseline() {
        var gate = newGate();
        gate.movedTo(100, 100);
        gate.allowStationarySample();
        compare(gate.movedTo(300, 300), true);
        compare(gate.movedTo(300, 300), false);
    }
}

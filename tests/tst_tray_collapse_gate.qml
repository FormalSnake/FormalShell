import QtQuick
import QtTest
import "../shell/Components"

// Arm/cancel state machine for shell/Surfaces/Bar/widgets/Tray.qml's
// auto-collapse timer (M20 Task 5d). Drives the real component's own
// rowEntered()/rowExited()/menuOpened()/menuClosed()/freshExpansion()/
// collapsed() calls and asserts `armed` — the same instantiate-the-real-
// component approach tst_pointer_move_gate.qml uses for its own pure
// decision object.
TestCase {
    id: testCase
    name: "TrayCollapseGate"

    Component {
        id: gateComponent

        TrayCollapseGate {}
    }

    function newGate() {
        var gate = createTemporaryObject(gateComponent, testCase);
        verify(gate);
        return gate;
    }

    function test_never_entered_never_arms() {
        var gate = newGate();
        gate.freshExpansion();
        gate.rowExited();
        compare(gate.armed, false);
    }

    function test_entered_then_left_arms() {
        var gate = newGate();
        gate.freshExpansion();
        gate.rowEntered();
        gate.rowExited();
        compare(gate.armed, true);
    }

    function test_reentry_cancels() {
        var gate = newGate();
        gate.freshExpansion();
        gate.rowEntered();
        gate.rowExited();
        compare(gate.armed, true);
        gate.rowEntered();
        compare(gate.armed, false);
    }

    function test_reexit_rearms_after_reentry() {
        var gate = newGate();
        gate.freshExpansion();
        gate.rowEntered();
        gate.rowExited();
        gate.rowEntered();
        gate.rowExited();
        compare(gate.armed, true);
    }

    function test_menu_open_holds() {
        var gate = newGate();
        gate.freshExpansion();
        gate.rowEntered();
        gate.rowExited();
        gate.menuOpened();
        compare(gate.armed, false);
    }

    function test_menu_close_restarts_the_exit_clock() {
        var gate = newGate();
        gate.freshExpansion();
        gate.rowEntered();
        gate.rowExited();
        gate.menuOpened();
        gate.menuClosed();
        compare(gate.armed, true);
    }

    // A menu opened while the pointer is still over the row must keep
    // collapse held even once the pointer leaves, until the menu itself
    // closes too.
    function test_menu_open_outlasts_row_exit() {
        var gate = newGate();
        gate.freshExpansion();
        gate.rowEntered();
        gate.menuOpened();
        gate.rowExited();
        compare(gate.armed, false);
        gate.menuClosed();
        compare(gate.armed, true);
    }

    function test_fresh_expansion_resets_visited() {
        var gate = newGate();
        gate.freshExpansion();
        gate.rowEntered();
        gate.rowExited();
        compare(gate.armed, true);
        gate.freshExpansion();
        compare(gate.armed, false);
    }

    function test_collapsed_resets_visited() {
        var gate = newGate();
        gate.freshExpansion();
        gate.rowEntered();
        gate.rowExited();
        compare(gate.armed, true);
        gate.collapsed();
        compare(gate.armed, false);
    }
}

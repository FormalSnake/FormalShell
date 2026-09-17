import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Components/SizeMorph.qml's rule (DESIGN.md §1 "Motion", M51 D5, M57 D7):
// the size tracks its content's target while the surface is open, freezes
// while it is closed, is seeded without a clock on each open, and travels
// from the moment the surface is mapped rather than from its enter having
// settled.
TestCase {
    id: testCase
    name: "SizeMorph"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component {
        id: morphComponent
        SizeMorph {}
    }

    property bool _originalMotionEnabled

    function init() {
        testCase._originalMotionEnabled = Theme.motionEnabled;
    }

    function cleanup() {
        Theme.motionEnabled = testCase._originalMotionEnabled;
    }

    function test_an_open_surface_travels_to_its_new_target() {
        var morph = createTemporaryObject(morphComponent, testCase, { target: 100, open: true });
        compare(morph.value, 100);
        morph.target = 300;
        // The clock is armed and carrying it: the size is still where it was
        // on the tick of the change, not already at the target.
        verify(morph.running);
        compare(morph.value, 100);
        tryCompare(morph, "value", 300, 2000);
        verify(!morph.running);
    }

    // A change landing on a closing surface must not move it: the centre
    // seens every pending row on close(), and the launcher's own route is
    // resolved before the card has left.
    function test_a_closed_surface_is_frozen() {
        var morph = createTemporaryObject(morphComponent, testCase, { target: 100, open: true });
        morph.open = false;
        morph.target = 400;
        compare(morph.value, 100);
        verify(!morph.running);
    }

    // And the next open lands on the real content size rather than gliding
    // there from whatever the last close froze.
    function test_the_next_open_is_seeded_without_a_clock() {
        var morph = createTemporaryObject(morphComponent, testCase, { target: 100, open: true });
        morph.open = false;
        morph.target = 400;
        morph.open = true;
        compare(morph.value, 400);
        verify(!morph.running);
    }

    // The gate is the surface being on screen (M57 D7): content that lands
    // behind a window still coming up has nothing to animate in front of, and
    // content that lands once it is up travels even though the enter itself
    // has not settled.
    function test_a_change_behind_an_unmapped_window_lands_at_once() {
        var morph = createTemporaryObject(morphComponent, testCase,
            { target: 100, open: true, mapped: false });
        morph.target = 300;
        compare(morph.value, 300);
        verify(!morph.running);
    }

    function test_a_change_once_the_window_is_up_travels() {
        var morph = createTemporaryObject(morphComponent, testCase,
            { target: 100, open: true, mapped: false });
        morph.mapped = true;
        morph.target = 500;
        verify(morph.running);
        compare(morph.value, 100);
        tryCompare(morph, "value", 500, 2000);
    }

    // Panel's handoff draws its own trajectory over this size, so nothing
    // may run under it: one clock on a size, never two.
    function test_a_bypassed_morph_lands_on_the_target() {
        var morph = createTemporaryObject(morphComponent, testCase,
            { target: 100, open: true, bypass: true });
        morph.target = 300;
        compare(morph.value, 300);
        verify(!morph.running);
    }

    // A card whose content is rebuilt on every open (the chevron's second
    // bar and the tray's) measures itself while it is arriving, and that
    // first width has to be there rather than grown into.
    function test_a_held_morph_lands_at_once_and_travels_once_let_go() {
        var morph = createTemporaryObject(morphComponent, testCase,
            { target: 100, open: true, held: true });
        morph.target = 300;
        compare(morph.value, 300);
        verify(!morph.running);
        morph.held = false;
        morph.target = 500;
        verify(morph.running);
        tryCompare(morph, "value", 500, 2000);
    }

    // A second change part way through the first one turns the same clock
    // around from where it is rather than restarting from the stale size.
    function test_a_retarget_mid_flight_carries_on_from_where_it_is() {
        var morph = createTemporaryObject(morphComponent, testCase, { target: 100, open: true });
        morph.target = 600;
        // Wait for the travel to have moved, not for a wall-clock slice of
        // it: a slow runner can spend 60ms before the first animation frame.
        tryVerify(function () { return morph.value > 100; }, 1000);
        var caught = morph.value;
        verify(caught < 600);
        morph.target = 200;
        verify(morph.running);
        tryCompare(morph, "value", 200, 2000);
    }

    function test_motion_disabled_is_instant() {
        Theme.motionEnabled = false;
        var morph = createTemporaryObject(morphComponent, testCase, { target: 100, open: true });
        morph.target = 400;
        compare(morph.value, 400);
    }
}

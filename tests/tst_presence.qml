import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Presence's lifecycle (DESIGN.md §1 "Motion", M51 D2/D4): `shown` tracks
// `open` immediately but lags `close()` until the exit settles, `center`
// never slides, and `motion.enabled: false` collapses the whole recipe to
// an instant swap.
TestCase {
    id: testCase
    name: "Presence"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component {
        id: presenceComponent
        Presence {}
    }

    property bool _originalMotionEnabled

    function init() {
        testCase._originalMotionEnabled = Theme.motionEnabled;
    }

    function cleanup() {
        Theme.motionEnabled = testCase._originalMotionEnabled;
    }

    function test_open_flips_shown_true_immediately() {
        var presence = createTemporaryObject(presenceComponent, testCase, { edge: "top" });
        compare(presence.shown, false);
        presence.open = true;
        compare(presence.shown, true);
    }

    function test_close_keeps_shown_until_the_exit_settles() {
        var presence = createTemporaryObject(presenceComponent, testCase, { edge: "top", open: true });
        compare(presence.shown, true);
        presence.open = false;
        // The exit Behavior is still running: shown must not drop on the
        // same tick close() does.
        compare(presence.shown, true);
        tryCompare(presence, "shown", false, 1000);
        compare(presence.opacity, 0);
    }

    function test_center_edge_never_slides() {
        var presence = createTemporaryObject(presenceComponent, testCase, { edge: "center" });
        compare(presence.slideX, 0);
        compare(presence.slideY, 0);
        presence.open = true;
        compare(presence.slideX, 0);
        compare(presence.slideY, 0);
        tryCompare(presence, "shown", true, 1000);
        compare(presence.slideX, 0);
        compare(presence.slideY, 0);
    }

    function test_settled_drops_during_the_exit_and_returns_after() {
        var presence = createTemporaryObject(presenceComponent, testCase, { edge: "top", open: true });
        compare(presence.settled, true);
        presence.open = false;
        // The exit Behavior has just started: settled must not read true
        // again until it actually finishes, or a size morph gated on it
        // would race the fade with a stale value.
        compare(presence.settled, false);
        tryCompare(presence, "settled", true, 1000);
    }

    function test_motion_disabled_is_instant() {
        Theme.motionEnabled = false;
        var presence = createTemporaryObject(presenceComponent, testCase, { edge: "top" });
        presence.open = true;
        // No Behavior to wait out: motion.enabled=false zeros both surface
        // durations (Theme/tokens.js's motionTokens), so the whole recipe
        // lands on the same tick.
        compare(presence.shown, true);
        compare(presence.opacity, 1);
        compare(presence.scale, 1);
        compare(presence.slideX, 0);
        compare(presence.slideY, 0);
        presence.open = false;
        compare(presence.shown, false);
    }
}

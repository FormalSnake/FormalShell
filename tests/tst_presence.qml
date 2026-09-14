import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Presence's lifecycle (DESIGN.md §1 "Motion", M51 D2/D4, M54 D8): `shown`
// tracks `open` immediately but lags `close()` until the exit settles, a
// `fade` zooms from 0.97 and never travels, `emerge` sits a closed card its
// whole extent behind its edge while `unfold` carries a card's own size
// instead, and `motion.enabled: false` collapses every mode to an instant
// swap.
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

    function test_a_fade_zooms_but_never_travels() {
        // M54 D8: the 8px nudge is gone, and what is left of the arrival is
        // the scale, which rides a clock of its own.
        var presence = createTemporaryObject(presenceComponent, testCase, { edge: "center" });
        compare(presence.scale, 0.97);
        compare(presence.emergeX, 0);
        compare(presence.emergeY, 0);
        presence.open = true;
        tryCompare(presence, "settled", true, 2000);
        compare(presence.scale, 1);
        compare(presence.emergeX, 0);
        compare(presence.emergeY, 0);
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

    function test_bypass_lands_on_the_pose_open_names() {
        // Panel's handoff (M53 D5) draws its own trajectory and must have no
        // fade and no zoom running under it.
        var presence = createTemporaryObject(presenceComponent, testCase, { edge: "top", bypass: true });
        presence.open = true;
        compare(presence.opacity, 1);
        compare(presence.scale, 1);
        compare(presence.settled, true);
        compare(presence.shown, true);
    }

    function test_bypass_holds_the_pose_through_an_interruption() {
        var presence = createTemporaryObject(presenceComponent, testCase, { edge: "top", open: true });
        presence.open = false;
        // Mid-exit: the bypass has to read the pose `open` names rather than
        // wherever the fade had got to, or a surface handed the card back
        // would pop to a third of its opacity.
        presence.bypass = true;
        presence.open = true;
        compare(presence.opacity, 1);
        compare(presence.settled, true);
    }

    // --- emerge (M53 addendum, the drawer) -------------------------------

    function test_emerge_sits_a_closed_card_its_whole_extent_behind_the_edge() {
        var presence = createTemporaryObject(presenceComponent, testCase,
            { edge: "top", mode: "emerge", extent: 300 });
        // Toward the edge, so a top-anchored card is displaced upward.
        compare(presence.emergeY, -300);
        compare(presence.emergeX, 0);
        presence.open = true;
        tryCompare(presence, "settled", true, 2000);
        compare(presence.emergeY, 0);
    }

    function test_emerge_never_fades_or_zooms_the_card() {
        var presence = createTemporaryObject(presenceComponent, testCase,
            { edge: "bottom", mode: "emerge", extent: 120 });
        presence.open = true;
        // The clip at the edge is what hides the card, so its own opacity
        // and scale stay put for the whole travel.
        compare(presence.opacity, 1);
        compare(presence.scale, 1);
        tryCompare(presence, "settled", true, 2000);
        compare(presence.opacity, 1);
        compare(presence.scale, 1);
    }

    function test_emerge_holds_its_contents_back_until_the_card_is_out() {
        var presence = createTemporaryObject(presenceComponent, testCase,
            { edge: "top", mode: "emerge", extent: 300 });
        compare(presence.contentOpacity, 0);
        presence.open = true;
        tryCompare(presence, "settled", true, 2000);
        compare(presence.contentOpacity, 1);
    }

    function test_emerge_retargets_mid_travel_rather_than_snapping() {
        var presence = createTemporaryObject(presenceComponent, testCase,
            { edge: "bottom", mode: "emerge", extent: 400 });
        presence.open = true;
        // Wait for the travel to have moved, not for a wall-clock slice of
        // it: a slow runner can spend 60ms before the first animation frame.
        tryVerify(function () { return presence.emergeY < 400; }, 1000);
        presence.open = false;
        // Part way out: a re-toggle turns the same travel around from where
        // it is, so the card is neither at rest nor back behind the edge.
        verify(presence.emergeY > 0);
        verify(presence.emergeY < 400);
        tryCompare(presence, "shown", false, 2000);
        // Past `shown`, not past the clock: the spatial curve overshoots, so
        // the card is further behind the edge than its own extent for the
        // tail of the exit and comes back to it (M54 D1). The window is
        // already unmapped by then, which is why `shown` may drop first.
        tryCompare(presence, "settled", true, 2000);
        compare(presence.emergeY, 400);
    }

    function test_emerge_is_instant_with_motion_disabled() {
        Theme.motionEnabled = false;
        var presence = createTemporaryObject(presenceComponent, testCase,
            { edge: "top", mode: "emerge", extent: 300 });
        presence.open = true;
        compare(presence.shown, true);
        compare(presence.emergeY, 0);
        compare(presence.contentOpacity, 1);
        presence.open = false;
        compare(presence.shown, false);
        compare(presence.emergeY, -300);
    }

    // --- unfold (M53 addendum, the launcher) -----------------------------

    function test_unfold_carries_its_morph_from_the_fold_to_the_card() {
        var presence = createTemporaryObject(presenceComponent, testCase,
            { edge: "center", mode: "unfold" });
        compare(presence.morph, 0);
        presence.open = true;
        tryCompare(presence, "settled", true, 2000);
        compare(presence.morph, 1);
        compare(presence.scale, 1);
        compare(presence.emergeX, 0);
        compare(presence.emergeY, 0);
    }

    function test_unfold_stays_shown_while_the_card_is_still_folding_back() {
        var presence = createTemporaryObject(presenceComponent, testCase,
            { edge: "center", mode: "unfold", open: true });
        tryCompare(presence, "settled", true, 2000);
        presence.open = false;
        // The card leaves on `effectsFast` and the fold on `spatial`, so the
        // window has to stay mapped for the slower of the two.
        compare(presence.shown, true);
        verify(presence.morph > 0);
        tryCompare(presence, "shown", false, 2000);
        // The fold overshoots below its own seed on the way out and settles
        // back on it, behind a window that has already gone.
        tryCompare(presence, "settled", true, 2000);
        compare(presence.morph, 0);
    }

    function test_unfold_is_instant_with_motion_disabled() {
        Theme.motionEnabled = false;
        var presence = createTemporaryObject(presenceComponent, testCase,
            { edge: "center", mode: "unfold" });
        presence.open = true;
        compare(presence.shown, true);
        compare(presence.morph, 1);
        compare(presence.opacity, 1);
        compare(presence.contentOpacity, 1);
        presence.open = false;
        compare(presence.shown, false);
        compare(presence.morph, 0);
    }

    function test_motion_disabled_is_instant() {
        Theme.motionEnabled = false;
        var presence = createTemporaryObject(presenceComponent, testCase, { edge: "top" });
        presence.open = true;
        // No Behavior to wait out: motion.enabled=false zeros every duration
        // (Theme/tokens.js's motionTokens), so the whole recipe lands on the
        // same tick.
        compare(presence.shown, true);
        compare(presence.opacity, 1);
        compare(presence.scale, 1);
        presence.open = false;
        compare(presence.shown, false);
    }
}

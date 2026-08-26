import QtQuick
import QtTest
import "../shell/HotCorners/arm.js" as Arm

TestCase {
    name: "HotCornersArm"

    // A corner that never fires is just armed, and a dwell cut short by the
    // pointer moving away leaves it that way.
    function test_a_fresh_corner_is_armed() {
        var s = Arm.initial();
        verify(Arm.isArmed(s, 0));
        s = Arm.onExit(s);
        verify(Arm.isArmed(s, 0));
        s = Arm.onEnter(s, 0);
        verify(Arm.isArmed(s, 0));
    }

    function test_firing_disarms_until_the_action_ends() {
        var s = Arm.onFire(Arm.initial(), 1000, true);
        verify(!Arm.isArmed(s, 1000));
        // The lock plate taking the pointer is not the pointer leaving.
        s = Arm.onExit(s);
        verify(!Arm.isArmed(s, 60000));
    }

    // The bug: unlocking with the cursor parked in the corner. The action
    // ends, the compositor hands the pointer back, and that enter must not
    // fire the corner again.
    function test_the_hand_back_after_an_unlock_does_not_re_arm() {
        var s = Arm.onFire(Arm.initial(), 1000, true);
        s = Arm.onExit(s);
        s = Arm.onActionEnd(s, 5000, true);
        verify(!Arm.isArmed(s, 5000));
        s = Arm.onEnter(s, 5005);
        verify(!Arm.isArmed(s, 5005));
        // Still parked a long while later: nothing has left, so nothing arms.
        verify(!Arm.isArmed(s, 60000));
    }

    // The same hand-back on a compositor that drops the surface's hover
    // state while the action owns the pointer, so the corner reads
    // pointerInside false even though the cursor never moved. The enter
    // inside the cooldown is what catches it.
    function test_an_enter_inside_the_cooldown_cancels_the_leave_before_it() {
        var s = Arm.onFire(Arm.initial(), 1000, true);
        s = Arm.onActionEnd(s, 5000, false);
        s = Arm.onExit(s);
        s = Arm.onEnter(s, 5000 + Arm.REARM_COOLDOWN_MS - 1);
        verify(!Arm.isArmed(s, 60000));
    }

    function test_leaving_for_real_then_returning_fires_again() {
        var s = Arm.onFire(Arm.initial(), 1000, true);
        s = Arm.onActionEnd(s, 5000, true);
        s = Arm.onEnter(s, 5005);
        s = Arm.onExit(s);
        verify(Arm.isArmed(s, 5000 + Arm.REARM_COOLDOWN_MS));
        s = Arm.onEnter(s, 9000);
        verify(Arm.isArmed(s, 9000));
    }

    // The cursor was somewhere else when the action ended (the password was
    // typed, the pointer moved). Nothing has to leave, only the cooldown.
    function test_a_pointer_already_elsewhere_needs_only_the_cooldown() {
        var s = Arm.onFire(Arm.initial(), 1000, true);
        s = Arm.onActionEnd(s, 5000, false);
        verify(!Arm.isArmed(s, 5000 + Arm.REARM_COOLDOWN_MS - 1));
        verify(Arm.isArmed(s, 5000 + Arm.REARM_COOLDOWN_MS));
    }

    function test_the_cooldown_is_measured_from_the_end_not_the_fire() {
        var s = Arm.onFire(Arm.initial(), 1000, true);
        s = Arm.onExit(s);
        s = Arm.onActionEnd(s, 30000, false);
        verify(!Arm.isArmed(s, 30000 + Arm.REARM_COOLDOWN_MS - 1));
        verify(Arm.isArmed(s, 30000 + Arm.REARM_COOLDOWN_MS));
    }

    // A launcher action string and an external locker both report nothing
    // back, so their cooldown runs from the fire and the leave is the whole
    // guard.
    function test_an_action_with_no_reported_end_still_needs_a_leave() {
        var s = Arm.onFire(Arm.initial(), 1000, false);
        verify(!Arm.isArmed(s, 1000 + Arm.REARM_COOLDOWN_MS));
        s = Arm.onEnter(s, 1000 + Arm.REARM_COOLDOWN_MS);
        verify(!Arm.isArmed(s, 60000));
        s = Arm.onExit(s);
        verify(Arm.isArmed(s, 60000));
    }

    // Nothing of ours is running, so an end belonging to some other trigger
    // (a keybind lock, an idle screensaver) cannot disarm a corner.
    function test_an_end_with_nothing_pending_changes_nothing() {
        var s = Arm.onActionEnd(Arm.initial(), 1000, true);
        verify(Arm.isArmed(s, 1000));
        var fired = Arm.onFire(Arm.initial(), 1000, true);
        var ended = Arm.onActionEnd(fired, 5000, true);
        var again = Arm.onActionEnd(ended, 9000, true);
        compare(again.endedAtMs, 5000);
    }

    function test_which_actions_report_their_own_end() {
        verify(Arm.reportsEnd("lock", false));
        verify(!Arm.reportsEnd("lock", true));
        verify(Arm.reportsEnd("screensaver", false));
        verify(Arm.reportsEnd("screensaver", true));
        verify(!Arm.reportsEnd("@ipc:theme.toggleMode", false));
        verify(!Arm.reportsEnd("hyprctl dispatch workspace 1", false));
    }

    // A corner surface rebuilt while its own action is up (an output waking,
    // a settings.json save) must not come up armed, or the enter it gets at
    // unlock is the same relock by another road.
    function test_a_surface_built_while_the_action_runs_adopts_it() {
        var s = Arm.adopt(5000, true, 0);
        verify(!Arm.isArmed(s, 60000));
        s = Arm.onActionEnd(s, 6000, true);
        s = Arm.onEnter(s, 6050);
        verify(!Arm.isArmed(s, 60000));
        s = Arm.onExit(s);
        verify(Arm.isArmed(s, 60000));
    }

    function test_a_surface_built_inside_the_cooldown_adopts_the_rest_of_it() {
        var s = Arm.adopt(5000, false, 5000 - Arm.REARM_COOLDOWN_MS + 100);
        verify(!Arm.isArmed(s, 5000));
        // Nothing has left since, so the cooldown running out is not enough.
        verify(!Arm.isArmed(s, 60000));
        s = Arm.onExit(s);
        verify(Arm.isArmed(s, 60000));
    }

    function test_a_surface_built_with_nothing_pending_is_plainly_armed() {
        verify(Arm.isArmed(Arm.adopt(60000, false, 0), 60000));
        verify(Arm.isArmed(Arm.adopt(60000, false, 5000), 60000));
    }

    function test_the_cooldown_is_the_documented_number() {
        compare(Arm.REARM_COOLDOWN_MS, 400);
    }
}

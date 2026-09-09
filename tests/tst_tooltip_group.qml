import QtQuick
import QtTest
import "../shell/Components"

// The tooltip group's state machine (M53 D10): who owns the card, what the
// show costs, and whether the card travels to its next item or enters at it.
// Driven head-on rather than through Tooltip.qml, which is a layer-shell
// window; `drawn` is the one thing the surface answers, so a test sets it
// where a real Presence would.
TestCase {
    id: testCase
    name: "TooltipGroup"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component {
        id: groupComponent
        TooltipGroup {}
    }

    Component {
        id: anchorComponent
        Item { width: 40; height: 24 }
    }

    function make() {
        return createTemporaryObject(groupComponent, testCase);
    }

    function anchor() {
        return createTemporaryObject(anchorComponent, testCase);
    }

    // Every wait on the delay is generous: the assertion is that it elapsed
    // at all, never how long a loaded runner took to notice.
    function shows(group) {
        tryCompare(group, "shown", true, group.delay * 5);
    }

    function test_the_first_item_waits_the_delay_out() {
        var group = make();
        var cell = anchor();
        group.show(cell, "VOLUME 40%", "top");
        compare(group.shown, false);
        shows(group);
        compare(group.text, "VOLUME 40%");
        compare(group.barEdge, "top");
        compare(group.anchorItem, cell);
        // Nothing was on screen to hand over from.
        compare(group.travel, false);
    }

    function test_a_second_item_inside_the_grace_window_is_a_hand_off() {
        var group = make();
        var first = anchor();
        var second = anchor();
        group.show(first, "VOLUME 40%", "top");
        shows(group);
        // The surface is up, which is what makes the next show a hand-off
        // rather than an entrance.
        group.drawn = true;
        group.hide(first);
        compare(group.shown, false);

        group.show(second, "WIFI HOME", "top");
        compare(group.shown, true);
        compare(group.travel, true);
        compare(group.anchorItem, second);
        compare(group.text, "WIFI HOME");
    }

    // The card left before the pointer reached the next cell, so there is
    // nothing to travel: the show still skips the delay, and the card enters
    // at its new item rather than gliding out of a stale rect.
    function test_a_faded_card_inside_the_grace_window_still_skips_the_delay() {
        var group = make();
        var first = anchor();
        var second = anchor();
        group.show(first, "VOLUME 40%", "top");
        shows(group);
        group.drawn = true;
        group.hide(first);
        group.drawn = false;

        group.show(second, "WIFI HOME", "top");
        compare(group.shown, true);
        compare(group.travel, false);
    }

    function test_a_show_past_the_grace_window_waits_again() {
        var group = make();
        var first = anchor();
        var second = anchor();
        group.show(first, "VOLUME 40%", "top");
        shows(group);
        group.drawn = true;
        group.hide(first);
        group.drawn = false;
        wait(group.grace + 200);

        group.show(second, "WIFI HOME", "top");
        compare(group.shown, false);
        shows(group);
        compare(group.travel, false);
    }

    // A pointer crossing cells faster than the delay has shown nothing, so
    // no cell it passed opens the window for the next one.
    function test_a_hide_before_anything_showed_opens_no_grace_window() {
        var group = make();
        var first = anchor();
        var second = anchor();
        group.show(first, "VOLUME 40%", "top");
        group.hide(first);
        group.show(second, "WIFI HOME", "top");
        compare(group.shown, false);
        shows(group);
    }

    function test_a_value_ticking_under_a_parked_pointer_never_restarts_the_delay() {
        var group = make();
        var cell = anchor();
        group.show(cell, "VOLUME 40%", "top");
        // Still waiting: the second line replaces the first without the
        // delay starting over, so the card lands when the first show said.
        group.show(cell, "VOLUME 45%", "top");
        compare(group.shown, false);
        shows(group);
        compare(group.text, "VOLUME 45%");

        group.show(cell, "VOLUME 50%", "top");
        compare(group.shown, true);
        compare(group.text, "VOLUME 50%");
        compare(group.travel, false);
    }

    function test_a_leave_from_a_cell_that_no_longer_owns_the_card_is_ignored() {
        var group = make();
        var first = anchor();
        var second = anchor();
        group.show(first, "VOLUME 40%", "top");
        shows(group);
        group.drawn = true;
        group.hide(first);
        group.show(second, "WIFI HOME", "top");
        compare(group.shown, true);

        group.hide(first);
        compare(group.shown, true);
        compare(group.anchorItem, second);
    }

    // A cell destroyed under the card it owns nulls the group's handle on
    // it, and a card anchored to nothing is a rect nobody stands at.
    function test_the_card_goes_with_the_item_it_describes() {
        var group = make();
        var cell = anchor();
        group.show(cell, "VOLUME 40%", "top");
        shows(group);
        cell.destroy();
        tryCompare(group, "shown", false, 1000);
    }

    function test_an_empty_line_is_no_tooltip_at_all() {
        var group = make();
        var cell = anchor();
        group.show(cell, "", "top");
        compare(group.shown, false);
        wait(group.delay + 200);
        compare(group.shown, false);
    }
}

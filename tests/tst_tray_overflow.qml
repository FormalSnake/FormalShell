import QtQuick
import QtTest
import "../shell/Bar/tray.js" as Tray

TestCase {
    name: "TrayOverflow"

    // The numbers the bar actually works in: an icon-only cell is the body
    // font plus `controlPaddingX` either side (13 + 24), and the rail's gap
    // is `sm`.
    readonly property real cell: 37
    readonly property real gap: 4

    function fit(total, budget, maxVisible) {
        return Tray.fit(total, budget, cell, gap, maxVisible === undefined ? 0 : maxVisible);
    }

    // The default: no ceiling at all, so the strip never carries the tray
    // however much room it has.
    function test_by_default_the_tray_lives_in_the_second_bar() {
        var r = fit(4, 4000);
        compare(r.inline, 0);
        compare(r.hidden, 4);
    }

    function test_by_default_no_measurement_is_needed() {
        compare(Tray.needsRoom(4, 0), false);
        var r = fit(4, Number.POSITIVE_INFINITY);
        compare(r.inline, 0);
        compare(r.hidden, 4);
    }

    function test_no_items_means_no_toggle() {
        var r = fit(0, 400);
        compare(r.inline, 0);
        compare(r.hidden, 0);
        compare(Tray.needsRoom(0, 0), false);
    }

    // -1 is "as many as fit", which is all of them or none of them.
    function test_room_mode_keeps_a_tray_that_fits() {
        var r = fit(4, 400, -1);
        compare(r.inline, 4);
        compare(r.hidden, 0);
    }

    // 4 cells and 3 gaps is 160 exactly. The toggle is never charged for: it
    // only exists once the tray has moved, and then it is the only thing on
    // the rail.
    function test_room_mode_an_exact_fit_stays_on_the_strip() {
        var r = fit(4, 160, -1);
        compare(r.inline, 4);
        compare(r.hidden, 0);
    }

    function test_room_mode_one_pixel_short_moves_the_whole_tray() {
        var r = fit(4, 159, -1);
        compare(r.inline, 0);
        compare(r.hidden, 4);
    }

    // Bar.qml's slack goes negative once the regions are already clipping.
    function test_room_mode_a_negative_budget_moves_the_whole_tray() {
        var r = fit(6, -120, -1);
        compare(r.inline, 0);
        compare(r.hidden, 6);
    }

    // An unmeasured strip cannot move the tray on its own: the rail waits
    // for a real number rather than answering this one.
    function test_room_mode_an_unmeasured_budget_shows_everything() {
        compare(Tray.needsRoom(9, -1), true);
        var r = fit(9, Number.POSITIVE_INFINITY, -1);
        compare(r.inline, 9);
        compare(r.hidden, 0);
    }

    // A cell of no width is a rail that has not been measured yet, not a
    // reason to move the tray.
    function test_room_mode_an_unmeasured_cell_shows_everything() {
        var r = Tray.fit(5, 100, 0, gap, -1);
        compare(r.inline, 5);
        compare(r.hidden, 0);
    }

    function test_a_ceiling_moves_a_tray_that_is_over_it() {
        var r = fit(6, 4000, 3);
        compare(r.inline, 0);
        compare(r.hidden, 6);
        compare(Tray.needsRoom(6, 3), false);
    }

    function test_a_ceiling_at_the_item_count_keeps_the_tray() {
        var r = fit(3, 4000, 3);
        compare(r.inline, 3);
        compare(r.hidden, 0);
    }

    // Room still has the last word under a ceiling the tray is inside.
    function test_room_wins_under_a_ceiling_the_tray_is_inside() {
        var r = fit(3, 100, 5);
        compare(r.inline, 0);
        compare(r.hidden, 3);
    }

    function test_extent_counts_the_gaps_between_cells_only() {
        compare(Tray.extent(0, cell, gap), 0);
        compare(Tray.extent(1, cell, gap), 37);
        compare(Tray.extent(3, cell, gap), 119);
    }
}

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

    function test_everything_fits_with_room_to_spare() {
        var r = fit(4, 400);
        compare(r.inline, 4);
        compare(r.hidden, 0);
    }

    // 4 cells and 3 gaps is 160 exactly. The toggle is never charged for
    // here: it only exists once the tray has already moved, and then it is
    // the only thing on the rail.
    function test_an_exact_fit_stays_on_the_strip() {
        var r = fit(4, 160);
        compare(r.inline, 4);
        compare(r.hidden, 0);
    }

    // All or nothing: one pixel short moves the whole tray, not one icon.
    function test_one_pixel_short_moves_the_whole_tray() {
        var r = fit(4, 159);
        compare(r.inline, 0);
        compare(r.hidden, 4);
    }

    function test_a_strip_with_no_room_at_all_moves_the_whole_tray() {
        var r = fit(6, 20);
        compare(r.inline, 0);
        compare(r.hidden, 6);
    }

    // Bar.qml's slack goes negative once the regions are already clipping.
    function test_a_negative_budget_moves_the_whole_tray() {
        var r = fit(6, -120);
        compare(r.inline, 0);
        compare(r.hidden, 6);
    }

    function test_an_unmeasured_budget_shows_everything() {
        var r = fit(9, Number.POSITIVE_INFINITY);
        compare(r.inline, 9);
        compare(r.hidden, 0);
    }

    function test_no_items_means_no_toggle() {
        var r = fit(0, 400);
        compare(r.inline, 0);
        compare(r.hidden, 0);
    }

    function test_max_visible_hands_over_a_tray_that_would_have_fit() {
        var r = fit(6, 4000, 3);
        compare(r.inline, 0);
        compare(r.hidden, 6);
    }

    function test_max_visible_at_the_item_count_keeps_the_tray() {
        var r = fit(3, 4000, 3);
        compare(r.inline, 3);
        compare(r.hidden, 0);
    }

    function test_max_visible_above_the_item_count_does_nothing() {
        var r = fit(2, 4000, 9);
        compare(r.inline, 2);
        compare(r.hidden, 0);
    }

    // The ceiling holds even where no measurement would: a Tray outside a
    // bar has an unbounded budget and still answers to it.
    function test_max_visible_holds_against_an_unmeasured_budget() {
        var r = fit(6, Number.POSITIVE_INFINITY, 3);
        compare(r.inline, 0);
        compare(r.hidden, 6);
    }

    // A cell of no width is a rail that has not been measured yet, not a
    // reason to hide the tray.
    function test_an_unmeasured_cell_shows_everything() {
        var r = Tray.fit(5, 100, 0, gap, 0);
        compare(r.inline, 5);
        compare(r.hidden, 0);
    }

    function test_extent_counts_the_gaps_between_cells_only() {
        compare(Tray.extent(0, cell, gap), 0);
        compare(Tray.extent(1, cell, gap), 37);
        compare(Tray.extent(3, cell, gap), 119);
    }
}

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

    // 4 cells and 3 gaps is 160 exactly, and the toggle is only charged for
    // once something is behind it, so the last item that fits still fits.
    function test_an_exact_fit_hides_nothing() {
        var r = fit(4, 160);
        compare(r.inline, 4);
        compare(r.hidden, 0);
    }

    function test_one_pixel_short_spills_into_the_second_bar() {
        var r = fit(4, 159);
        // The toggle takes a cell and a gap, leaving room for two.
        compare(r.inline, 2);
        compare(r.hidden, 2);
    }

    function test_a_strip_with_no_room_at_all_keeps_only_the_toggle() {
        var r = fit(6, 20);
        compare(r.inline, 0);
        compare(r.hidden, 6);
    }

    // Bar.qml's slack goes negative once the regions are already clipping.
    function test_a_negative_budget_keeps_only_the_toggle() {
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

    function test_max_visible_hides_items_that_would_have_fit() {
        var r = fit(6, 4000, 3);
        compare(r.inline, 3);
        compare(r.hidden, 3);
    }

    function test_max_visible_above_the_item_count_does_nothing() {
        var r = fit(2, 4000, 9);
        compare(r.inline, 2);
        compare(r.hidden, 0);
    }

    // The ceiling is a ceiling, never a floor: a strip too short for it
    // still gives up cells.
    function test_room_wins_over_max_visible_when_it_is_tighter() {
        var r = fit(6, 100, 3);
        compare(r.inline, 1);
        compare(r.hidden, 5);
    }

    // A capped tray pays for the toggle before it measures, since the cap
    // has already made the toggle certain.
    function test_a_capped_tray_charges_for_the_toggle() {
        // 3 cells, 2 gaps and the toggle with its own gap is 160.
        compare(fit(6, 160, 3).inline, 3);
        compare(fit(6, 159, 3).inline, 2);
    }

    // A cell of no width is a rail that has not been measured yet, not a
    // reason to hide the whole tray.
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

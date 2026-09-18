import QtQuick
import QtTest
import "../shell/Menu/appgrid.js" as AppGrid
import "../shell/Theme/themes/metamorphosis.js" as Metamorphosis
import "../shell/Theme/themes/pantheon.js" as Pantheon

// The launcher's app grid (M58): the column maths and the cursor walk, the
// two things the view cannot state for itself. What a cell draws is the
// rig's job (`--app-grid`); what the cursor does when the level is half a
// grid and half a list is this file's.
TestCase {
    name: "MenuAppGrid"

    function app(id) { return { id: id, kind: "app", label: id }; }
    function row(id) { return { id: id, kind: "action", label: id }; }

    function test_columns_fill_the_width_at_the_minimum_cell() {
        compare(AppGrid.columnsFor(536, 128), 4);
        compare(AppGrid.columnsFor(816, 128), 6);
    }

    // A card too narrow for one cell still draws a column: no answer here is
    // ever 0, which would divide the width by nothing.
    function test_a_card_narrower_than_a_cell_still_draws_one_column() {
        compare(AppGrid.columnsFor(100, 128), 1);
        compare(AppGrid.columnsFor(0, 128), 1);
        compare(AppGrid.columnsFor(536, 0), 1);
    }

    // The split is stable: both blocks come out in the order the ranking
    // gave them, so nothing here re-scores anything.
    function test_apps_lead_and_both_blocks_keep_their_order() {
        var out = AppGrid.partition([app("a"), row("x"), app("b"), row("y"), app("c")]);
        compare(out.appCount, 3);
        compare(out.rows.map(function (r) { return r.id; }).join(","), "a,b,c,x,y");
    }

    function test_a_level_of_only_apps_is_all_grid() {
        var out = AppGrid.partition([app("a"), app("b")]);
        compare(out.appCount, 2);
        compare(out.rows.length, 2);
    }

    // No apps means no grid at all, which is what Menu.qml reads `appCount`
    // for: the level stays the row list it was.
    function test_a_level_with_no_apps_is_left_alone() {
        var rows = [row("x"), row("y")];
        var out = AppGrid.partition(rows);
        compare(out.appCount, 0);
        compare(out.rows.length, 2);
        compare(out.rows[0].id, "x");
    }

    function test_an_empty_level_partitions_to_nothing() {
        compare(AppGrid.partition([]).appCount, 0);
        compare(AppGrid.partition(null).rows.length, 0);
    }

    // Inside the cells a vertical press is a whole row of them.
    function test_a_press_inside_the_grid_moves_by_a_column_count() {
        compare(AppGrid.verticalStep(4, 0, 8, 8), 4);
        compare(AppGrid.verticalStep(-4, 7, 8, 8), -4);
    }

    // Down out of the last row of cells lands on the first row under the
    // grid rather than skipping past three of them.
    function test_down_out_of_the_grid_lands_on_the_first_row_under_it() {
        compare(AppGrid.verticalStep(4, 5, 6, 9), 1);
        compare(AppGrid.verticalStep(4, 4, 6, 9), 2);
    }

    // With nothing under the grid the step is unchanged, so the caller's own
    // wrap carries the cursor back to the top of the cells.
    function test_down_off_a_grid_with_no_rows_under_it_still_wraps() {
        compare(AppGrid.verticalStep(4, 5, 6, 6), 4);
    }

    // Under the grid the rows are a list, so they move by a row either way,
    // and up out of the first one lands back on the cell above it.
    function test_the_rows_under_the_grid_move_by_a_row() {
        compare(AppGrid.verticalStep(4, 6, 6, 9), 1);
        compare(AppGrid.verticalStep(-4, 6, 6, 9), -1);
        compare(AppGrid.verticalStep(-4, 8, 6, 9), -1);
    }

    function test_an_empty_level_moves_nothing() {
        compare(AppGrid.verticalStep(4, 0, 0, 0), 4);
        compare(AppGrid.verticalStep(0, 3, 6, 9), 0);
    }

    // M60 P6: the route the launcher opens on follows the theme table's
    // launcher habit, which is what Menu.qml passes as the default of its
    // `menu.appGrid` read, so an explicit key in settings.json still wins
    // over both.
    function test_the_grid_is_the_default_the_launcher_habit_asks_for() {
        compare(AppGrid.defaultFor(Pantheon.STYLE.habits.launcher), true);
        compare(AppGrid.defaultFor(Metamorphosis.STYLE.habits.launcher), false);
        compare(AppGrid.defaultFor(undefined), false);
    }

    // A few hundred installed apps is the real case, and the split runs on
    // every keystroke. One pass over the rows, never a scan per row.
    function test_the_split_stays_linear_over_a_real_app_list() {
        var rows = [];
        for (var i = 0; i < 600; i++)
            rows.push(i % 5 === 0 ? row("r" + i) : app("a" + i));
        var t0 = new Date().getTime();
        for (var pass = 0; pass < 50; pass++)
            AppGrid.partition(rows);
        var elapsed = new Date().getTime() - t0;
        verify(elapsed < 200, "50 splits of 600 rows took " + elapsed + "ms");
    }
}

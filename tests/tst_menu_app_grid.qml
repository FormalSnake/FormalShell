import QtQuick
import QtTest
import "../shell/Menu/appgrid.js" as AppGrid

// The launcher's app grid (M58): the column maths and the split, the two
// things the view cannot state for itself. What a cell draws is the rig's
// job (`--app-grid`), and the cursor walk is tst_menu_nav.qml's.
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

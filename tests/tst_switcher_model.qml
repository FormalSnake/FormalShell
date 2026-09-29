import QtQuick
import QtTest
import "../shell/Surfaces/Switcher/switcher.js" as Switcher

// The window switcher's list and its cursor (M60 T6, M64): Gala's order, the
// one workspace it lists, the wrap at either end of the row, the grid a row
// too long for the output breaks into, and the empty case a session with
// nothing to switch between gives.
TestCase {
    name: "SwitcherModel"

    function win(id, workspaceId) {
        return { id: id, title: id + " window", appId: id, workspaceId: workspaceId || "1" };
    }

    readonly property var three: [win("0xa"), win("0xb"), win("0xc")]

    // The compositor lists windows in its own order; the switcher lists the
    // most recently focused first, so one Alt+Tab lands on the window before
    // the current one.
    function test_the_most_recently_focused_comes_first() {
        var out = Switcher.entries(three, ["0xc", "0xa"]);
        compare(out.length, 3);
        compare(out[0].id, "0xc");
        compare(out[1].id, "0xa");
        compare(out[2].id, "0xb");
    }

    // A window nothing has focused this session keeps the compositor's own
    // order behind the ones that have, rather than being dropped.
    function test_an_unfocused_window_keeps_its_place_at_the_back() {
        var out = Switcher.entries(three, []);
        compare(out.length, 3);
        compare(out[0].id, "0xa");
        compare(out[2].id, "0xc");
    }

    // A history carrying an id that has since closed names nothing, and the
    // rest of the order survives it.
    function test_a_closed_window_in_the_history_is_skipped() {
        var out = Switcher.entries(three, ["0xdead", "0xb"]);
        compare(out.length, 3);
        compare(out[0].id, "0xb");
    }

    // Special workspaces are overlays rather than places, and the quake
    // console lives on one permanently: offering it would offer a window the
    // user never put there.
    function test_a_window_on_a_special_workspace_is_not_offered() {
        var windows = [win("0xa"), win("0xconsole", "-99"), win("0xb")];
        var out = Switcher.entries(windows, []);
        compare(out.length, 2);
        compare(out[0].id, "0xa");
        compare(out[1].id, "0xb");
    }

    // Gala lists the ACTIVE workspace's windows and no others
    // (`handle_switch_windows` hands `get_active_workspace ()` to
    // `collect_all_windows`). Ours does the same, which is what stops a quick
    // Alt+Tab committing to a window somewhere else and taking the compositor
    // there (owner, 2026-09-18).
    function test_only_the_workspace_being_looked_at_is_offered() {
        var windows = [win("0xa", "1"), win("0xelsewhere", "2"), win("0xb", "1")];
        var out = Switcher.entries(windows, ["0xelsewhere", "0xb"], "1");
        compare(out.length, 2);
        compare(out[0].id, "0xb");
        compare(out[1].id, "0xa");
    }

    // The history is the session's, not one workspace's, so an id on it that
    // names a window elsewhere names nothing here rather than pulling that
    // window onto the card.
    function test_a_history_entry_from_another_workspace_offers_nothing() {
        var windows = [win("0xa", "1"), win("0xelsewhere", "2")];
        var out = Switcher.entries(windows, ["0xelsewhere"], "1");
        compare(out.length, 1);
        compare(out[0].id, "0xa");
    }

    // One window on the workspace is still a card, the way Gala shows one:
    // the cursor's single step wraps onto it, so a tap leaves focus put.
    function test_one_window_on_the_workspace_is_the_only_entry() {
        var windows = [win("0xa", "1"), win("0xelsewhere", "2")];
        var out = Switcher.entries(windows, [], "1");
        compare(out.length, 1);
        compare(Switcher.advance(0, out.length, 1), 0);
    }

    // A workspace whose windows have all gone offers none, which is the cell
    // saying so rather than the rest of the session.
    function test_an_empty_workspace_offers_none_of_the_others() {
        var windows = [win("0xelsewhere", "2"), win("0xalso", "3")];
        compare(Switcher.entries(windows, ["0xelsewhere"], "1").length, 0);
    }

    // No workspace named is no filter at all, the convention
    // shell/Compositor/focus.js takes for the same value.
    function test_an_empty_workspace_id_filters_nothing() {
        var windows = [win("0xa", "1"), win("0xelsewhere", "2")];
        compare(Switcher.entries(windows, [], "").length, 2);
        compare(Switcher.entries(windows, []).length, 2);
    }

    function test_the_empty_case_is_an_empty_list() {
        compare(Switcher.entries([], ["0xa"]).length, 0);
        compare(Switcher.entries(undefined, undefined).length, 0);
    }

    // The cursor wraps both ways, and a list with nothing in it has no
    // cursor to move.
    function test_the_cursor_wraps_at_either_end() {
        compare(Switcher.advance(0, 3, 1), 1);
        compare(Switcher.advance(2, 3, 1), 0);
        compare(Switcher.advance(0, 3, -1), 2);
        compare(Switcher.advance(1, 3, -1), 0);
        compare(Switcher.advance(0, 0, 1), 0);
        compare(Switcher.advance(4, 0, -1), 0);
    }

    // A thumbnail keeps its window's aspect at the cell's fixed height, held
    // between a floor and a ceiling so no cell collapses or sprawls.
    function test_a_thumbnail_keeps_its_window_aspect() {
        compare(Switcher.thumbWidth({ width: 1600, height: 900 }, 100, 60, 300), 178);
        compare(Switcher.thumbWidth({ width: 900, height: 900 }, 100, 60, 300), 100);
        compare(Switcher.thumbWidth({ width: 300, height: 900 }, 100, 60, 300), 60);
        compare(Switcher.thumbWidth({ width: 3840, height: 400 }, 100, 60, 300), 300);
    }

    // A window whose rect the compositor has not reported reads as 16:9.
    function test_a_window_with_no_rect_reads_as_sixteen_by_nine() {
        compare(Switcher.thumbWidth(undefined, 90, 40, 400), 160);
        compare(Switcher.thumbWidth({ width: 0, height: 0 }, 90, 40, 400), 160);
    }

    function test_cells_that_fit_stay_on_one_row() {
        var out = Switcher.layout([100, 150, 100], 0, 400);
        compare(out.rows.length, 1);
        compare(out.rows[0].count, 3);
        compare(out.width, 350);
    }

    // Eleven equal cells over a row holding seven read as 6 and 5.
    function test_a_row_too_long_for_the_output_wraps_balanced() {
        var widths = [];
        for (var i = 0; i < 11; i++)
            widths.push(100);
        var out = Switcher.layout(widths, 0, 700);
        compare(out.rows.length, 2);
        compare(out.rows[0].first, 0);
        compare(out.rows[0].count, 6);
        compare(out.rows[1].first, 6);
        compare(out.rows[1].count, 5);
        compare(out.width, 600);
    }

    // Different widths pack by their sum, and the gap counts between cells.
    function test_mixed_widths_wrap_by_their_sum() {
        var out = Switcher.layout([300, 300, 300], 10, 620);
        compare(out.rows.length, 2);
        compare(out.rows[0].count, 2);
        compare(out.rows[0].width, 610);
        compare(out.rows[1].count, 1);
        compare(out.width, 610);
    }

    // A cell wider than the output still gets a row, cramped and never empty.
    function test_a_cell_wider_than_the_output_still_draws() {
        var out = Switcher.layout([500, 100], 0, 300);
        compare(out.rows.length, 2);
        compare(out.rows[0].count, 1);
        compare(out.width, 500);
    }

    function test_no_windows_is_no_grid_at_all() {
        compare(Switcher.layout([], 0, 700).rows.length, 0);
        compare(Switcher.layout(undefined, 0, 700).width, 0);
    }

    // Rows stack at the cell height and each is centred on the widest; the
    // balanced wrap here is 200 over 200 and 100.
    function test_cells_sit_in_centred_rows() {
        var grid = Switcher.layout([200, 200, 100], 0, 400);
        compare(grid.width, 300);
        var out = Switcher.cells(grid, 50);
        compare(out.length, 3);
        compare(out[0].x, 50);
        compare(out[0].y, 0);
        compare(out[1].x, 0);
        compare(out[1].y, 50);
        compare(out[2].x, 200);
        compare(out[2].width, 100);
        compare(out[2].row, 1);
    }

    function test_the_row_holding_an_entry_is_found() {
        var out = Switcher.layout([100, 100, 100, 100], 0, 200);
        compare(Switcher.rowOf(out.rows, 0), 0);
        compare(Switcher.rowOf(out.rows, 1), 0);
        compare(Switcher.rowOf(out.rows, 2), 1);
        compare(Switcher.rowOf(out.rows, 3), 1);
        compare(Switcher.rowOf(out.rows, 4), -1);
    }

    // Several windows of one app count off in row order; an app with one
    // window, and a window nothing could name, carry no count at all.
    function test_windows_of_one_app_count_off_in_row_order() {
        var marks = Switcher.ordinals(["entry:foot", "entry:mpv", "entry:foot", "", "", "entry:foot"]);
        compare(marks.length, 6);
        compare(marks[0].n, 1);
        compare(marks[0].of, 3);
        compare(marks[2].n, 2);
        compare(marks[5].n, 3);
        compare(marks[1].of, 1);
        compare(marks[3].of, 1);
        compare(marks[4].of, 1);
        compare(Switcher.ordinals(undefined).length, 0);
    }
}

import QtQuick
import QtTest
import "../shell/Menu/nav.js" as Nav

// The launcher's cursor and key policy (M72 T1, Menu/nav.js): where the
// cursor lands when the rows change under it, where one key moves it on a
// row list, a grid and the app grid's two halves, and which keys belong to
// the results rather than to the search field.
TestCase {
    name: "MenuNav"

    // --- Re-derivation ----------------------------------------------------

    // Clipboard or window churn inserts a row above a cursor the reader put
    // somewhere: the cursor stays on its row rather than on its old slot.
    function test_a_placed_cursor_keeps_its_row_when_rows_arrive_above_it() {
        compare(Nav.rederive("b", 1, ["x", "a", "b", "c"], false, true), 2);
    }

    function test_a_placed_cursor_keeps_its_row_when_rows_leave_above_it() {
        compare(Nav.rederive("c", 3, ["a", "c"], false, true), 1);
    }

    // The row it was on left: whatever took its slot, clamped to what is
    // left, and never past the end, which is where Enter used to do nothing.
    function test_a_row_that_left_hands_the_cursor_to_its_slot() {
        compare(Nav.rederive("b", 1, ["a", "c", "d"], false, true), 1);
        compare(Nav.rederive("z", 7, ["a", "c"], false, true), 1);
    }

    // The desktop entries reload one at a time, so the row the cursor was
    // put on can leave and come back: it gets the cursor back rather than
    // the cursor staying on whatever it was clamped to meanwhile.
    function test_a_row_that_comes_back_gets_the_cursor_back() {
        compare(Nav.rederive("b", 1, ["c"], false, true), 0);
        compare(Nav.rederive("b", 0, [], false, true), 0);
        compare(Nav.rederive("b", 0, ["a", "b", "c"], false, true), 1);
    }

    // A `when` condition resolving after the open inserts rows above the one
    // the cursor started on: nobody put it there, so it stays on the head.
    function test_an_unplaced_cursor_stays_on_the_first_row() {
        compare(Nav.rederive("b", 0, ["x", "y", "b"], false, false), 0);
    }

    // A new query, level or open always starts on the first row, even when
    // the row the cursor was on survived it.
    function test_a_fresh_list_starts_on_its_first_row() {
        compare(Nav.rederive("b", 1, ["a", "b"], true, true), 0);
    }

    function test_an_empty_list_puts_the_cursor_at_zero() {
        compare(Nav.rederive("b", 3, [], false, true), 0);
        compare(Nav.rederive("", 0, ["a"], false, true), 0);
    }

    // --- Row list ---------------------------------------------------------

    function test_a_row_list_steps_and_wraps() {
        compare(Nav.step(0, "down", 5, 0, 1, 3).index, 1);
        verify(Nav.step(0, "down", 5, 0, 1, 3).travels);
        compare(Nav.step(4, "down", 5, 0, 1, 3).index, 0);
        verify(!Nav.step(4, "down", 5, 0, 1, 3).travels);
        compare(Nav.step(0, "up", 5, 0, 1, 3).index, 4);
        verify(!Nav.step(0, "up", 5, 0, 1, 3).travels);
    }

    function test_page_home_and_end_jump_without_wrapping() {
        compare(Nav.step(1, "pageDown", 20, 0, 1, 6).index, 7);
        compare(Nav.step(17, "pageDown", 20, 0, 1, 6).index, 19);
        compare(Nav.step(3, "pageUp", 20, 0, 1, 6).index, 0);
        compare(Nav.step(9, "home", 20, 0, 1, 6).index, 0);
        compare(Nav.step(2, "end", 20, 0, 1, 6).index, 19);
        verify(!Nav.step(1, "pageDown", 20, 0, 1, 6).travels);
    }

    function test_an_empty_list_goes_nowhere() {
        compare(Nav.step(0, "down", 0, 0, 1, 1).index, 0);
    }

    // --- Grid (picker, emoji) ----------------------------------------------

    // Ten cells over four columns: rows 0-3, 4-7 and a short 8-9.
    function test_down_off_the_grid_wraps_to_the_same_column() {
        compare(Nav.step(9, "down", 10, 10, 4, 4).index, 1);
        compare(Nav.step(8, "down", 10, 10, 4, 4).index, 0);
    }

    // The old `raw % n` wrap lost the column whenever the cell count was not
    // a multiple of the column count.
    function test_up_off_the_grid_keeps_the_column_over_a_short_last_row() {
        compare(Nav.step(1, "up", 10, 10, 4, 4).index, 9);
        compare(Nav.step(3, "up", 10, 10, 4, 4).index, 7);
        compare(Nav.step(0, "up", 12, 12, 4, 4).index, 8);
    }

    // A column the short last row does not reach goes down onto the last
    // cell rather than skipping out of the grid.
    function test_down_into_a_short_last_row_lands_on_its_last_cell() {
        compare(Nav.step(7, "down", 10, 10, 4, 4).index, 9);
        compare(Nav.step(5, "down", 10, 10, 4, 4).index, 9);
        compare(Nav.step(4, "down", 10, 10, 4, 4).index, 8);
    }

    // Left on the first result used to wrap to the last one.
    function test_left_and_right_walk_reading_order_and_stop_at_the_ends() {
        compare(Nav.step(3, "right", 10, 10, 4, 4).index, 4);
        compare(Nav.step(4, "left", 10, 10, 4, 4).index, 3);
        compare(Nav.step(0, "left", 10, 10, 4, 4).index, 0);
        compare(Nav.step(9, "right", 10, 10, 4, 4).index, 9);
    }

    // --- App grid: six cells over four columns, three rows under them ------

    function test_down_out_of_the_cells_lands_on_the_first_row_under_them() {
        compare(Nav.step(5, "down", 9, 6, 4, 4).index, 6);
        compare(Nav.step(4, "down", 9, 6, 4, 4).index, 6);
        compare(Nav.step(1, "down", 9, 6, 4, 4).index, 5);
    }

    function test_the_rows_under_the_cells_move_by_a_row() {
        compare(Nav.step(6, "down", 9, 6, 4, 4).index, 7);
        compare(Nav.step(7, "up", 9, 6, 4, 4).index, 6);
        compare(Nav.step(6, "up", 9, 6, 4, 4).index, 5);
    }

    function test_the_app_grid_wraps_through_its_rows() {
        compare(Nav.step(8, "down", 9, 6, 4, 4).index, 0);
        compare(Nav.step(2, "up", 9, 6, 4, 4).index, 8);
    }

    // A query no app matches leaves the grid with no cells, and the rows
    // under it are then a plain list.
    function test_an_app_grid_with_no_cells_is_a_row_list() {
        compare(Nav.step(0, "down", 3, 0, 4, 4).index, 1);
        compare(Nav.step(0, "up", 3, 0, 4, 4).index, 2);
    }

    // --- Key policy ---------------------------------------------------------

    function ctx(extra) {
        var c = { mode: "menu", query: false, grid: false, appView: false, scrollable: false, variants: false };
        for (var k in extra)
            c[k] = extra[k];
        return c;
    }

    function test_arrows_walk_the_results() {
        compare(Nav.keyAction(Qt.Key_Up, 0, false, ctx({})), "up");
        compare(Nav.keyAction(Qt.Key_Down, 0, false, ctx({ query: true })), "down");
        compare(Nav.keyAction(Qt.Key_Left, 0, false, ctx({ grid: true })), "left");
        compare(Nav.keyAction(Qt.Key_Right, 0, false, ctx({ grid: true, query: true })), "right");
    }

    // On a row list Left/Right are the caret's; on a grid, Ctrl+Left/Right
    // still are, which is what keeps a typo fixable while the grid owns the
    // plain arrows.
    function test_the_caret_keeps_ctrl_arrows_and_plain_arrows_on_a_list() {
        compare(Nav.keyAction(Qt.Key_Left, 0, false, ctx({ query: true })), "pass");
        compare(Nav.keyAction(Qt.Key_Left, Qt.ControlModifier, false, ctx({ grid: true, query: true })), "pass");
        compare(Nav.keyAction(Qt.Key_Right, Qt.ControlModifier, false, ctx({ grid: true, query: true })), "pass");
        compare(Nav.keyAction(Qt.Key_Left, Qt.ShiftModifier, false, ctx({ grid: true, query: true })), "pass");
    }

    function test_ctrl_backspace_with_a_query_is_the_fields() {
        compare(Nav.keyAction(Qt.Key_Backspace, Qt.ControlModifier, false, ctx({ query: true })), "pass");
        compare(Nav.keyAction(Qt.Key_Backspace, 0, true, ctx({ query: true })), "pass");
    }

    // A held Backspace that outlived its text used to walk the whole tree and
    // close the launcher.
    function test_backspace_on_an_empty_field_pops_once_per_press() {
        compare(Nav.keyAction(Qt.Key_Backspace, 0, false, ctx({})), "pop");
        compare(Nav.keyAction(Qt.Key_Backspace, 0, true, ctx({})), "swallow");
        compare(Nav.keyAction(Qt.Key_Backspace, 0, false, ctx({ mode: "select" })), "pass");
    }

    function test_escape_clears_then_pops() {
        compare(Nav.keyAction(Qt.Key_Escape, 0, false, ctx({ query: true })), "clear");
        compare(Nav.keyAction(Qt.Key_Escape, 0, false, ctx({})), "pop");
        compare(Nav.keyAction(Qt.Key_Escape, 0, false, ctx({ mode: "select", query: true })), "clear");
        compare(Nav.keyAction(Qt.Key_Escape, 0, false, ctx({ mode: "select" })), "close");
        compare(Nav.keyAction(Qt.Key_Escape, 0, false, ctx({ mode: "input", query: true })), "close");
    }

    function test_tab_never_leaves_the_field() {
        compare(Nav.keyAction(Qt.Key_Tab, 0, false, ctx({})), "swallow");
        compare(Nav.keyAction(Qt.Key_Backtab, Qt.ShiftModifier, false, ctx({})), "swallow");
        compare(Nav.keyAction(Qt.Key_Tab, 0, false, ctx({ variants: true })), "variant");
    }

    function test_page_home_and_end_go_to_the_results() {
        compare(Nav.keyAction(Qt.Key_PageDown, 0, false, ctx({})), "pageDown");
        compare(Nav.keyAction(Qt.Key_PageUp, 0, false, ctx({ grid: true })), "pageUp");
        compare(Nav.keyAction(Qt.Key_Home, 0, false, ctx({ query: true })), "home");
        compare(Nav.keyAction(Qt.Key_End, 0, false, ctx({ query: true })), "end");
        compare(Nav.keyAction(Qt.Key_Home, Qt.ShiftModifier, false, ctx({ query: true })), "pass");
        compare(Nav.keyAction(Qt.Key_End, 0, false, ctx({ mode: "input", query: true })), "pass");
    }

    function test_an_app_view_scrolls_instead() {
        compare(Nav.keyAction(Qt.Key_Down, 0, false, ctx({ appView: true })), "scrollDown");
        compare(Nav.keyAction(Qt.Key_PageDown, 0, false, ctx({ appView: true, scrollable: true })), "scrollPageDown");
        compare(Nav.keyAction(Qt.Key_PageDown, 0, false, ctx({ appView: true })), "pass");
        compare(Nav.keyAction(Qt.Key_Home, 0, false, ctx({ appView: true, scrollable: true })), "scrollHome");
        compare(Nav.keyAction(Qt.Key_Left, 0, false, ctx({ appView: true, grid: true })), "pass");
    }

    function test_enter_activates_and_shift_enter_is_the_alternate() {
        compare(Nav.keyAction(Qt.Key_Return, 0, false, ctx({})), "activate");
        compare(Nav.keyAction(Qt.Key_Enter, Qt.ShiftModifier, false, ctx({})), "activateAlternate");
        compare(Nav.keyAction(Qt.Key_Return, 0, false, ctx({ mode: "input" })), "submit");
    }

    function test_printable_keys_are_the_fields() {
        compare(Nav.keyAction(Qt.Key_A, 0, false, ctx({ grid: true })), "pass");
    }
}

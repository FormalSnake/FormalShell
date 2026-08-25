import QtQuick
import QtTest
import "../shell/Components/cursor.js" as Cursor

// Panel.qml's keyboard cursor (spec "Keyboard model", M41 Task 4). Panel
// imports Quickshell, so the arithmetic it drives lives in cursor.js and is
// tested head-on, the same split tst_theme_tokens and tst_menu_search use.
TestCase {
    name: "PanelCursor"

    function test_first_move_reveals_without_moving() {
        var next = Cursor.move(2, 5, false, 0, 1);
        compare(next.index, 2);
        compare(next.active, true);
    }

    function test_second_move_steps() {
        compare(Cursor.move(2, 5, true, 0, 1).index, 3);
        compare(Cursor.move(2, 5, true, 0, -1).index, 1);
    }

    function test_horizontal_moves_when_there_is_no_vertical_delta() {
        compare(Cursor.move(0, 5, true, 1, 0).index, 1);
        compare(Cursor.move(3, 5, true, -1, 0).index, 2);
        // A diagonal is vertical: one call covers both axes of a list.
        compare(Cursor.move(0, 5, true, 1, 1).index, 1);
    }

    function test_a_grid_steps_a_whole_row_vertically() {
        // Calendar's 7-column month: down from the first Monday lands on
        // the second Monday, not on Tuesday.
        compare(Cursor.move(0, 42, true, 0, 1, 7).index, 7);
        compare(Cursor.move(14, 42, true, 0, -1, 7).index, 7);
    }

    function test_a_grid_stops_horizontally_at_the_ends_of_its_own_row() {
        compare(Cursor.move(7, 42, true, -1, 0, 7).index, 7);
        compare(Cursor.move(13, 42, true, 1, 0, 7).index, 13);
        compare(Cursor.move(8, 42, true, -1, 0, 7).index, 7);
    }

    function test_a_grid_clamps_vertically_at_the_grid_edges() {
        compare(Cursor.move(3, 42, true, 0, -1, 7).index, 0);
        compare(Cursor.move(38, 42, true, 0, 1, 7).index, 41);
    }

    function test_one_column_behaves_exactly_like_a_list() {
        compare(Cursor.move(2, 5, true, 0, 1, 1).index, 3);
        compare(Cursor.move(2, 5, true, 1, 0, 1).index, 3);
    }

    function test_move_clamps_at_both_ends() {
        compare(Cursor.move(0, 5, true, 0, -1).index, 0);
        compare(Cursor.move(4, 5, true, 0, 1).index, 4);
    }

    function test_move_on_an_empty_list_stays_at_zero() {
        compare(Cursor.move(3, 0, true, 0, 1).index, 0);
        compare(Cursor.move(0, 0, false, 0, 1).index, 0);
    }

    function test_clamp_pulls_a_stale_index_back_into_range() {
        compare(Cursor.clamp(9, 5), 4);
        compare(Cursor.clamp(-3, 5), 0);
        compare(Cursor.clamp(2, 0), 0);
    }

    function test_activation_reports_the_row_under_the_cursor() {
        compare(Cursor.activation(2, 5, true, 0), 2);
        compare(Cursor.activation(9, 5, true, 0), 4);
    }

    function test_activation_is_nothing_before_the_cursor_is_revealed() {
        compare(Cursor.activation(2, 5, false, 0), -1);
    }

    function test_activation_is_nothing_on_an_empty_row_list() {
        compare(Cursor.activation(0, 0, true, 0), -1);
    }

    function test_a_section_past_the_row_list_activates_with_no_rows() {
        compare(Cursor.activation(0, 0, true, 1), 0);
    }

    function test_section_wraps_both_ways() {
        compare(Cursor.section(0, 2, 1), 1);
        compare(Cursor.section(1, 2, 1), 0);
        compare(Cursor.section(0, 2, -1), 1);
    }

    function test_a_single_section_never_moves() {
        compare(Cursor.section(0, 1, 1), 0);
        compare(Cursor.section(0, 0, -1), 0);
    }

    function test_horizontal_is_a_step_only_on_a_panel_that_asked_for_one() {
        compare(Cursor.isStep(1, 0, true, true), true);
        compare(Cursor.isStep(-1, 0, true, true), true);
        compare(Cursor.isStep(1, 0, false, true), false);
    }

    function test_a_step_never_fires_before_the_cursor_is_revealed() {
        compare(Cursor.isStep(1, 0, true, false), false);
    }

    function test_vertical_is_never_a_step() {
        compare(Cursor.isStep(0, 1, true, true), false);
        compare(Cursor.isStep(1, 1, true, true), false);
    }

    function test_the_catcher_is_blocked_while_an_inline_editor_has_focus() {
        compare(Cursor.catcherBlocked(true, true), true);
        compare(Cursor.catcherBlocked(true, false), false);
    }

    function test_the_catcher_is_blocked_on_a_closed_panel() {
        compare(Cursor.catcherBlocked(false, false), true);
    }
}

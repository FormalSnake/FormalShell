import QtQuick
import QtTest
import "../shell/Surfaces/Switcher/switcher.js" as Switcher

// The window switcher's list and its cursor (M60 T6): Gala's order, the wrap
// at either end of the row, the grid a row too long for the output breaks
// into, and the empty case a session with nothing to switch between gives.
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

    // One row while the cells fit, then balanced rows: eleven across a card
    // holding seven reads as 6 and 5 rather than as a full row and a stub.
    function test_a_row_too_long_for_the_output_wraps_balanced() {
        compare(Switcher.columns(3, 7), 3);
        compare(Switcher.columns(7, 7), 7);
        compare(Switcher.columns(8, 7), 4);
        compare(Switcher.columns(11, 7), 6);
        compare(Switcher.rows(11, 6), 2);
        compare(Switcher.rows(3, 3), 1);
    }

    // A card that can hold nothing across still holds one cell: a switcher
    // on a tiny output is cramped, never empty.
    function test_a_column_count_below_one_still_draws_a_cell() {
        compare(Switcher.columns(3, 0), 1);
        compare(Switcher.rows(3, 1), 3);
    }

    function test_no_windows_is_no_grid_at_all() {
        compare(Switcher.columns(0, 7), 0);
        compare(Switcher.rows(0, 0), 0);
    }
}

import QtQuick
import QtTest
import "../shell/Components/tooltip.js" as Placement

// M44 D6: Tooltip.qml's own geometry, in the anchor's window space (which
// is the output's, see tooltip.js). `gap` is Theme.space.md and `edge` is
// the screen padding every floating surface keeps (M48 D3), both at the
// default scale.
TestCase {
    name: "TooltipPlacement"

    readonly property var screen: ({ width: 1920, height: 1080 })
    readonly property var card: ({ width: 200, height: 24 })
    readonly property int gap: 6
    readonly property int edge: 12

    function place(anchor, size, side) {
        return Placement.placement(anchor, size || card, screen, gap, edge, side);
    }

    // A bar cell: barMargin down from the top, barCellHeight tall.
    function test_a_bar_cell_puts_the_card_a_gap_under_it() {
        var p = place({ x: 900, y: 6, width: 60, height: 28 });
        compare(p.y, 40);
        compare(p.side, "below");
        compare(p.slideX, 0);
        compare(p.slideY, -1);
    }

    function test_the_card_centres_on_the_anchor() {
        var p = place({ x: 900, y: 6, width: 60, height: 28 });
        compare(p.x, 830);
    }

    // A panel-header button sits below the bar, in a window of its own; the
    // card still lands a gap under the button rather than under the bar.
    function test_a_panel_header_button_anchors_to_itself() {
        var p = place({ x: 1870, y: 58, width: 32, height: 32 });
        compare(p.y, 96);
    }

    function test_a_cell_against_the_right_edge_is_held_inside_the_output() {
        var p = place({ x: 1890, y: 6, width: 24, height: 28 });
        compare(p.x, screen.width - card.width - edge);
    }

    function test_a_cell_against_the_left_edge_is_held_inside_the_output() {
        var p = place({ x: 2, y: 6, width: 24, height: 28 });
        compare(p.x, edge);
    }

    // The bottom row of a full-height surface (the notification centre) has
    // no room under it, so the card flips over the row instead.
    function test_no_room_below_flips_the_card_above() {
        var p = place({ x: 1400, y: 1040, width: 300, height: 28 });
        compare(p.side, "above");
        compare(p.slideY, 1);
        compare(p.y, 1040 - gap - card.height);
    }

    function test_a_flip_that_would_leave_the_output_stays_below() {
        var p = place({ x: 10, y: 4, width: 60, height: 1070 });
        compare(p.side, "below");
        compare(p.y, screen.height - card.height - edge);
    }

    // A card taller than the output cannot fit either way; it clamps to the
    // top margin rather than leaving the screen.
    function test_a_card_taller_than_the_output_clamps_to_the_top_margin() {
        var p = place({ x: 900, y: 500, width: 60, height: 28 }, { width: 200, height: 4000 });
        compare(p.y, edge);
    }

    // A card wider than the output has no centring left to do.
    function test_a_card_wider_than_the_output_clamps_to_the_left_margin() {
        var p = place({ x: 900, y: 6, width: 60, height: 28 }, { width: 4000, height: 24 });
        compare(p.x, edge);
    }

    // --- Which side a bar cell's card goes: away from the bar's edge -------

    function test_a_bar_edge_names_the_side_away_from_it() {
        compare(Placement.sideForBarEdge(""), "below");
        compare(Placement.sideForBarEdge("top"), "below");
        compare(Placement.sideForBarEdge("bottom"), "above");
        compare(Placement.sideForBarEdge("left"), "right");
        compare(Placement.sideForBarEdge("right"), "left");
    }

    // A cell on a bottom bar: barMargin up from the bottom edge.
    function test_a_bottom_bar_cell_puts_the_card_a_gap_over_it() {
        var p = place({ x: 900, y: 1046, width: 60, height: 28 }, card, "above");
        compare(p.side, "above");
        compare(p.y, 1046 - gap - card.height);
        compare(p.x, 830);
    }

    // A cell on a left bar: the card sits a gap to its right, centred on it.
    function test_a_left_bar_cell_puts_the_card_a_gap_beside_it() {
        var p = place({ x: 6, y: 300, width: 28, height: 60 }, card, "right");
        compare(p.side, "right");
        compare(p.x, 6 + 28 + gap);
        compare(p.y, 300 + 30 - card.height / 2);
        compare(p.slideX, -1);
        compare(p.slideY, 0);
    }

    function test_a_right_bar_cell_puts_the_card_a_gap_before_it() {
        var p = place({ x: 1886, y: 300, width: 28, height: 60 }, card, "left");
        compare(p.side, "left");
        compare(p.x, 1886 - gap - card.width);
        compare(p.slideX, 1);
    }

    // A sideways card with no room on its side flips across the anchor.
    function test_no_room_beside_flips_the_card_across() {
        var p = place({ x: 1800, y: 300, width: 28, height: 60 }, card, "right");
        compare(p.side, "left");
        compare(p.x, 1800 - gap - card.width);
    }

    // A sideways card against the top of the output is held inside it.
    function test_a_sideways_card_at_the_top_is_held_inside_the_output() {
        var p = place({ x: 6, y: 2, width: 28, height: 20 }, card, "right");
        compare(p.y, edge);
    }

    function test_an_unknown_side_reads_as_below() {
        var p = place({ x: 900, y: 6, width: 60, height: 28 }, card, "sideways");
        compare(p.side, "below");
    }

    // --- Where the anchor's window sits on the output ----------------------

    // A bar on the top or left edge, a panel, the launcher: all start at
    // the output's corner.
    function test_a_window_hugging_the_start_of_an_axis_sits_at_zero() {
        var o = Placement.windowOrigin({ top: true, bottom: false, left: true, right: true }, { width: 1920, height: 40 }, screen);
        compare(o.x, 0);
        compare(o.y, 0);
        var full = Placement.windowOrigin({ top: true, bottom: true, left: true, right: true }, { width: 1920, height: 1080 }, screen);
        compare(full.x, 0);
        compare(full.y, 0);
    }

    // A bar on the right or bottom edge hugs the far end of one axis.
    function test_a_right_bar_is_offset_by_its_own_width() {
        var o = Placement.windowOrigin({ top: true, bottom: true, left: false, right: true }, { width: 40, height: 1080 }, screen);
        compare(o.x, 1880);
        compare(o.y, 0);
    }

    function test_a_bottom_bar_is_offset_by_its_own_height() {
        var o = Placement.windowOrigin({ top: false, bottom: true, left: true, right: true }, { width: 1920, height: 40 }, screen);
        compare(o.x, 0);
        compare(o.y, 1040);
    }
}

import QtQuick
import QtTest
import "../shell/Components/tooltip.js" as Placement

// M44 D6: Tooltip.qml's own geometry, in the anchor's window space (which
// is the output's, see tooltip.js). `gap` is Theme.space.md and `edge` is
// Theme.space.panelGap at the default scale.
TestCase {
    name: "TooltipPlacement"

    readonly property var screen: ({ width: 1920, height: 1080 })
    readonly property var card: ({ width: 200, height: 24 })
    readonly property int gap: 6
    readonly property int edge: 14

    function place(anchor, size) {
        return Placement.placement(anchor, size || card, screen, gap, edge);
    }

    // A bar cell: barMargin down from the top, barCellHeight tall.
    function test_a_bar_cell_puts_the_card_a_gap_under_it() {
        var p = place({ x: 900, y: 6, width: 60, height: 28 });
        compare(p.y, 40);
        compare(p.above, false);
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
        compare(p.above, true);
        compare(p.y, 1040 - gap - card.height);
    }

    function test_a_flip_that_would_leave_the_output_stays_below() {
        var p = place({ x: 10, y: 4, width: 60, height: 1070 });
        compare(p.above, false);
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
}

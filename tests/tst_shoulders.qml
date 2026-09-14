import QtQuick
import QtTest
import "../shell/Components/shoulders.js" as Outline

// Components/Shoulders.qml's outline: a 200x100 item under a top bar with a
// radius of 20, so the card itself is 160 wide between two 20px fillets.
TestCase {
    name: "Shoulders"

    function at(p, n) { return [Math.round(p.p[n].x), Math.round(p.p[n].y)]; }

    // Attached: the fillets' outer ends on the line, 20 outside the card's
    // sides, and the card's near edge open on the line.
    function test_attached_fillets_land_on_the_line_outside_the_card() {
        var o = Outline.outline("top", 200, 100, 20, 0, 0, 20);
        compare(at(o, 0), [0, 0]);
        compare(at(o, 1), [20, 20]);
        compare(at(o, 6), [180, 20]);
        compare(at(o, 7), [200, 0]);
        compare(o.nearConcave, true);
        compare(o.nearRadius, 20);
        compare(o.overhang, 20);
    }

    // Let go: a plain card with four rounded corners, its near edge the
    // neck in from the line and the corner arcs inside the card.
    function test_let_go_is_a_card_with_four_rounded_corners_off_the_line() {
        var o = Outline.outline("top", 200, 100, 20, 0, 7, -20);
        compare(at(o, 0), [40, 7]);
        compare(at(o, 1), [20, 27]);
        compare(at(o, 6), [180, 27]);
        compare(at(o, 7), [160, 7]);
        compare(o.nearConcave, false);
        compare(o.nearRadius, 20);
    }

    // Half way: sharp near corners on the card's own sides.
    function test_half_way_the_near_corners_are_sharp() {
        var o = Outline.outline("top", 200, 100, 20, 0, 3.5, 0);
        compare(at(o, 0), [20, 4]);
        compare(at(o, 1), [20, 4]);
        compare(o.nearRadius, 0);
    }

    // A shape shallower than the radius caps the fillet at its depth, so
    // the arc never runs past the card's far edge.
    function test_a_shallow_shape_caps_the_fillet_at_its_depth() {
        var o = Outline.outline("top", 200, 8, 20, 0, 0, 20);
        compare(o.nearRadius, 8);
        compare(at(o, 0), [12, 0]);
        compare(Outline.filletRadius(20, 8), 8);
        compare(Outline.filletRadius(20, 30), 20);
        compare(Outline.filletRadius(-5, 30), 0);
    }

    // The stroke's fillet offsets outward by half a stroke and lands on the
    // same outer point the fill does, so the gap is one number either way.
    function test_the_stroke_shares_the_fills_outer_points() {
        var fill = Outline.outline("top", 200, 100, 20, 0, 0, 20);
        var line = Outline.outline("top", 200, 100, 20, 0.5, 0, 20);
        compare(Math.round(line.p[0].x * 10), Math.round(fill.p[0].x * 10));
        compare(line.nearRadius, 20.5);
    }

    // A card hanging off this one opens a gap in the far edge: the stroke
    // stops and resumes where the gap says, held to the edge's straight
    // run, and with no gap both ends sit on p4.
    function test_the_far_edge_opens_a_gap_for_a_card_hanging_off_it() {
        var whole = Outline.outline("top", 200, 100, 20, 0, 0, 20, null);
        compare(at(whole, 4), [160, 100]);
        compare([Math.round(whole.g[0].x), Math.round(whole.g[0].y)], [160, 100]);
        compare([Math.round(whole.g[1].x), Math.round(whole.g[1].y)], [160, 100]);
        var cut = Outline.outline("top", 200, 100, 20, 0, 0, 20, [60, 140]);
        compare([Math.round(cut.g[0].x), Math.round(cut.g[0].y)], [60, 100]);
        compare([Math.round(cut.g[1].x), Math.round(cut.g[1].y)], [140, 100]);
        var wide = Outline.outline("top", 200, 100, 20, 0, 0, 20, [0, 500]);
        compare(Math.round(wide.g[0].x), 40);
        compare(Math.round(wide.g[1].x), 160);
    }

    // A left bar mirrors the space: the fillets sit on x = 0 and run down
    // the item, and the sweep flag flips with it.
    function test_a_left_bar_maps_the_line_onto_x_zero() {
        var o = Outline.outline("left", 100, 200, 20, 0, 0, 20);
        compare(at(o, 0), [0, 0]);
        compare(at(o, 1), [20, 20]);
        compare(at(o, 7), [0, 200]);
        compare(o.mirrored, true);
    }
}

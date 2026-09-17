import QtQuick
import QtTest
import "../shell/Components/shoulders.js" as Outline

// Components/Shoulders.qml's outline: a 200x100 item under a top bar with a
// radius of 20, so the card itself is 160 wide between two 20px fillets.
// The walled cases below take a 212x120 item instead: the card runs 26 out
// to a wall at one end, which the item keeps room for on both, and one more
// fillet past its far edge for the corner against that wall.
TestCase {
    name: "Shoulders"

    function at(p, n) { return [Math.round(p.p[n].x), Math.round(p.p[n].y)]; }

    // The two corners on the line, and the two on the far edge, in path
    // order: arcs 0 and 3 are the ones a card at rest rounds off the line.
    function nearArc(p) { return p.arcs[0]; }
    function farArc(p) { return p.arcs[1]; }

    // Attached: the fillets' outer ends on the line, 20 outside the card's
    // sides, and the card's near edge open on the line.
    function test_attached_fillets_land_on_the_line_outside_the_card() {
        var o = Outline.outline("top", 200, 100, 20, 0, 0, 20);
        compare(at(o, 0), [0, 0]);
        compare(at(o, 1), [20, 20]);
        compare(at(o, 6), [180, 20]);
        compare(at(o, 7), [200, 0]);
        compare(nearArc(o).concave, true);
        compare(nearArc(o).r, 20);
        compare(o.overhang, 20);
        compare(o.farOverhang, 0);
        compare(o.walled, [false, false]);
    }

    // Let go: a plain card with four rounded corners, its near edge the
    // neck in from the line and the corner arcs inside the card.
    function test_let_go_is_a_card_with_four_rounded_corners_off_the_line() {
        var o = Outline.outline("top", 200, 100, 20, 0, 7, -20);
        compare(at(o, 0), [40, 7]);
        compare(at(o, 1), [20, 27]);
        compare(at(o, 6), [180, 27]);
        compare(at(o, 7), [160, 7]);
        compare(nearArc(o).concave, false);
        compare(nearArc(o).r, 20);
    }

    // Half way: sharp near corners on the card's own sides.
    function test_half_way_the_near_corners_are_sharp() {
        var o = Outline.outline("top", 200, 100, 20, 0, 3.5, 0);
        compare(at(o, 0), [20, 4]);
        compare(at(o, 1), [20, 4]);
        compare(nearArc(o).r, 0);
    }

    // A shape shallower than the radius caps the fillet at its depth, so
    // the arc never runs past the card's far edge.
    function test_a_shallow_shape_caps_the_fillet_at_its_depth() {
        var o = Outline.outline("top", 200, 8, 20, 0, 0, 20);
        compare(nearArc(o).r, 8);
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
        compare(nearArc(line).r, 20.5);
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

    // The near fillet's centre, for a top edge: the corner of the box its
    // quarter arc sweeps, which is p0's column and p1's row.
    function nearCentre(p) { return [p.p[0].x, p.p[1].y]; }

    // Attached, the fill starts one border in from the line: that row is the
    // line's own window's, and two translucent fills over it read as a seam.
    function test_an_attached_fill_starts_one_border_in_from_the_line() {
        var o = Outline.outline("top", 200, 100, 20, 0, 0, 20, null, 1);
        compare(at(o, 0), [0, 1]);
        compare(at(o, 1), [20, 21]);
        compare(nearArc(o).r, 20);
        // The far corners and the card's far edge are where they were.
        compare(at(o, 3), [40, 100]);
        compare(farArc(o).r, 20);
    }

    // And the two fillets are then concentric: one centre, the stroke's
    // radius half a border the larger, so the line hugs the fill it outlines
    // instead of running outside it along the arc.
    function test_the_attached_fillets_share_one_centre() {
        var fill = Outline.outline("top", 200, 100, 20, 0, 0, 20, null, 1);
        var line = Outline.outline("top", 200, 100, 20, 0.5, 0, 20, null, 0);
        compare(nearCentre(fill), nearCentre(line));
        compare(nearArc(line).r - nearArc(fill).r, 0.5);
        // The same on a shape shallower than the radius, where both are
        // capped off the one depth.
        var shallowFill = Outline.outline("top", 200, 8, 20, 0, 0, 20, null, 1);
        var shallowLine = Outline.outline("top", 200, 8, 20, 0.5, 0, 20, null, 0);
        compare(nearCentre(shallowFill), nearCentre(shallowLine));
        compare(nearArc(shallowLine).r - nearArc(shallowFill).r, 0.5);
    }

    // Let go, the lip goes with the attach clock, so the fill is the card's
    // own rect: the same outline as a call that never learned about a line.
    function test_a_let_go_fill_is_the_plain_card_outline() {
        var free = Outline.outline("top", 200, 100, 20, 0, 7, -20, null, 0);
        var plain = Outline.outline("top", 200, 100, 20, 0, 7, -20);
        for (var k = 0; k < plain.p.length; k++) {
            compare(free.p[k].x, plain.p[k].x);
            compare(free.p[k].y, plain.p[k].y);
        }
        compare(nearArc(free).r, nearArc(plain).r);
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

    // --- Walls -----------------------------------------------------------

    // The room the item keeps: enough for a fillet, or for the longer run
    // out to a wall, and one radius past the card's far edge while any side
    // is walled, for the fillet that corner carries against the wall.
    function test_a_walled_side_sets_the_items_own_room() {
        compare(Outline.overhang(20, -1, -1), 20);
        compare(Outline.overhang(20, -1, 26), 26);
        compare(Outline.overhang(20, 12, -1), 20);
        compare(Outline.farOverhang(20, -1, -1), 0);
        compare(Outline.farOverhang(20, -1, 0), 20);
    }

    // Attached and walled at the end: the fill runs out to the wall, one
    // border short of it, square where it meets the line, and the corner on
    // the far edge is the near fillet turned a quarter against the wall, one
    // radius past the card's own far edge.
    function test_a_walled_end_runs_the_silhouette_out_to_the_wall() {
        var o = Outline.outline("top", 212, 120, 20, 0, 0, 20, null, 1,
            { start: -1, end: 26, attach: 1 });
        compare(o.walled, [false, true]);
        compare(o.overhang, 26);
        compare(o.farOverhang, 20);
        // The unwalled end of the card is where it always was.
        compare(at(o, 0), [6, 1]);
        compare(at(o, 1), [26, 21]);
        compare(at(o, 3), [46, 100]);
        // The wall fillet: off the far edge one radius in from the wall, out
        // to the wall one radius past that edge.
        compare(at(o, 4), [191, 100]);
        compare(at(o, 5), [211, 120]);
        compare(o.arcs[2].concave, true);
        compare(o.arcs[2].r, 20);
        // And the corner on the line is square, both its points on the wall.
        compare(at(o, 6), [211, 1]);
        compare(at(o, 7), [211, 1]);
        compare(o.arcs[3].r, 0);
    }

    // Fill and stroke stay concentric on the wall fillet too: one centre,
    // the stroke's radius half a border the larger, and the fillet's outer
    // point on the item's own far edge either way.
    function test_the_wall_fillet_shares_one_centre() {
        var walls = { start: -1, end: 26, attach: 1 };
        var fill = Outline.outline("top", 212, 120, 20, 0, 0, 20, null, 1, walls);
        var line = Outline.outline("top", 212, 120, 20, 0.5, 0, 20, null, 0, walls);
        compare([fill.p[4].x, fill.p[5].y], [line.p[4].x, line.p[5].y]);
        compare(line.arcs[2].r - fill.arcs[2].r, 0.5);
    }

    // Half way out: the walled side has pulled half its room back off the
    // wall and its two corners are sharp, like the near ones.
    function test_a_walled_end_pulls_off_the_wall_on_the_attach_clock() {
        var o = Outline.outline("top", 212, 120, 20, 0, 3.5, 0, null, 0.5,
            { start: -1, end: 26, attach: 0.5 });
        compare(at(o, 4), [199, 100]);
        compare(at(o, 5), [199, 100]);
        compare(at(o, 6), [199, 4]);
        compare(o.arcs[2].r, 0);
        compare(o.arcs[3].r, 0);
    }

    // And at 0 it is the plain card again, moved only by the room the item
    // keeps for the wall it no longer reaches.
    function test_a_let_go_walled_outline_is_the_plain_card() {
        var walled = Outline.outline("top", 212, 120, 20, 0, 7, -20, null, 0,
            { start: -1, end: 26, attach: 0 });
        var plain = Outline.outline("top", 200, 100, 20, 0, 7, -20);
        for (var k = 0; k < plain.p.length; k++) {
            compare(walled.p[k].x - plain.p[k].x, 6);
            compare(walled.p[k].y, plain.p[k].y);
        }
        for (var a = 0; a < plain.arcs.length; a++) {
            compare(walled.arcs[a].r, plain.arcs[a].r);
            compare(walled.arcs[a].concave, plain.arcs[a].concave);
        }
    }

    // A bottom bar mirrors the walled side with everything else: the wall at
    // the start of the line is the item's own left edge, and the fillet past
    // the card's far edge runs up rather than down.
    function test_a_bottom_bar_mirrors_a_walled_start() {
        var o = Outline.outline("bottom", 212, 120, 20, 0, 0, 20, null, 1,
            { start: 26, end: -1, attach: 1 });
        compare(o.walled, [true, false]);
        compare(o.mirrored, true);
        compare(at(o, 0), [1, 119]);
        compare(at(o, 1), [1, 119]);
        compare(at(o, 2), [1, 0]);
        compare(at(o, 3), [21, 20]);
        compare(o.arcs[0].r, 0);
        compare(o.arcs[1].concave, true);
        // The unwalled end still carries its own fillet on the line.
        compare(at(o, 7), [206, 119]);
    }

    // The gap a card hanging off this one opens is clamped to the far edge's
    // straight run, which a walled end shortens to where its fillet starts.
    function test_a_walled_end_shortens_the_far_edges_run() {
        var o = Outline.outline("top", 212, 120, 20, 0, 0, 20, [0, 500], 1,
            { start: -1, end: 26, attach: 1 });
        compare(Math.round(o.g[0].x), 46);
        compare(Math.round(o.g[1].x), 191);
    }
}

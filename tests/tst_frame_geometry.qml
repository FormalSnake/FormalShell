import QtQuick
import QtTest
import "../shell/Frame/geometry.js" as Geometry

// Surfaces/Frame/Frame.qml's band and cut-out, on a 1920x1080 output with a
// 40px bar, a 10px band and a 20px corner.
TestCase {
    name: "FrameGeometry"

    function inset(position) {
        return {
            top: position === "top" ? 40 : 0,
            bottom: position === "bottom" ? 40 : 0,
            left: position === "left" ? 40 : 0,
            right: position === "right" ? 40 : 0
        };
    }

    function edge(position, thickness) {
        var i = inset(position);
        return {
            top: i.top > 0 ? i.top : thickness,
            bottom: i.bottom > 0 ? i.bottom : thickness,
            left: i.left > 0 ? i.left : thickness,
            right: i.right > 0 ? i.right : thickness
        };
    }

    function frame(position, thickness, radius) {
        return Geometry.frameGeometry(1920, 1080, edge(position, thickness), radius);
    }

    // The ring is the whole output: the strip is painted here, not by the
    // bar, so the two never meet at a seam.
    function test_the_outer_rectangle_is_the_whole_output() {
        compare(JSON.stringify(frame("top", 10, 20).outer), JSON.stringify({ x: 0, y: 0, width: 1920, height: 1080 }));
    }

    // The cut-out is the band in from every edge but the bar's, where it
    // is the bar's own thickness in.
    function test_the_cut_out_clears_the_bar_and_the_band() {
        var g = frame("top", 10, 20);
        compare(JSON.stringify(g.inner), JSON.stringify({ x: 10, y: 40, width: 1900, height: 1030 }));
        var l = frame("left", 10, 20);
        compare(JSON.stringify(l.inner), JSON.stringify({ x: 40, y: 10, width: 1870, height: 1060 }));
        compare(g.radius, 20);
    }

    function test_a_radius_too_big_for_the_cut_out_is_capped() {
        compare(Geometry.frameGeometry(100, 60, edge("top", 10), 500).radius, 5);
        compare(frame("top", 10, -4).radius, 0);
    }

    function test_no_band_leaves_only_the_bar_cut_in() {
        var g = frame("top", 0, 20);
        compare(JSON.stringify(g.inner), JSON.stringify({ x: 0, y: 40, width: 1920, height: 1040 }));
    }

    // The hairline sits half a stroke inside the cut-out, so it lies in the
    // band rather than straddling its edge.
    function test_the_stroke_rect_is_half_a_stroke_inside() {
        var g = frame("top", 10, 20);
        var s = Geometry.strokeRect(g.inner, g.radius, 1);
        compare(s.x, 10.5);
        compare(s.y, 40.5);
        compare(s.width, 1899);
        compare(s.height, 1029);
        compare(s.radius, 19.5);
    }

    // --- The hairline's strokes (2026-09-14, the joined card on a framed screen)

    function line(position, gaps) {
        var g = frame(position, 10, 20);
        return Geometry.ringLine(g.inner, g.radius, gaps);
    }

    function test_no_gap_leaves_every_side_one_whole_run() {
        var l = line("top", {});
        compare(JSON.stringify(l.sides.top[0]), JSON.stringify({ x1: 30, y1: 40, x2: 1890, y2: 40 }));
        compare(l.sides.top[1].x1, l.sides.top[1].x2);
        compare(JSON.stringify(l.sides.left[0]), JSON.stringify({ x1: 10, y1: 60, x2: 10, y2: 1050 }));
        compare(l.corners.length, 4);
        compare(JSON.stringify(l.corners[3]),
            JSON.stringify({ x1: 10, y1: 60, x2: 30, y2: 40, gone: false }));
    }

    // --- The corner a walled card covers (M57 D2)
    //
    // A card out of a left bar's line that runs out to the ring's bottom line
    // draws that corner's own stretch of the cut-out itself, so the ring gives
    // the arc up: the card's gap covers the last radius of the left line and
    // its wall's gap the first radius of the bottom one.
    function test_a_corner_both_gaps_cover_is_given_up() {
        var l = line("left", { left: [539, 1085], bottom: [26, 426] });
        compare(l.corners[2].gone, true);
        compare(l.corners[0].gone, false);
        compare(l.corners[1].gone, false);
        compare(l.corners[3].gone, false);
    }

    // One side alone is not enough: a card resting near the end of a line
    // without running out to the other one never reaches the arc.
    function test_one_gap_alone_keeps_the_corner() {
        var l = line("left", { left: [539, 1085] });
        compare(l.corners[2].gone, false);
        var m = line("left", { bottom: [26, 426] });
        compare(m.corners[2].gone, false);
    }

    // And a shape still coming out from under the line covers only the first
    // pixels of the wall, not the arc: the corner stands until it does.
    function test_a_shallow_run_out_keeps_the_corner() {
        var l = line("left", { left: [539, 1085], bottom: [26, 45] });
        compare(l.corners[2].gone, false);
    }

    function test_a_gap_on_a_left_bar_splits_its_side_at_the_gap() {
        var l = line("left", { left: [300, 500] });
        compare(JSON.stringify(l.sides.left[0]), JSON.stringify({ x1: 40, y1: 30, x2: 40, y2: 300 }));
        compare(JSON.stringify(l.sides.left[1]), JSON.stringify({ x1: 40, y1: 500, x2: 40, y2: 1050 }));
        compare(l.sides.right[1].y1, l.sides.right[1].y2);
    }

    function test_two_sides_can_open_at_once() {
        var l = line("left", { left: [300, 500], right: [700, 900] });
        compare(l.sides.left[1].y1, 500);
        compare(l.sides.right[0].y2, 700);
        compare(l.sides.right[1].y1, 900);
    }

    function test_the_gap_is_held_to_the_straight_run() {
        var l = line("top", { top: [0, 5] });
        compare(l.sides.top[0].x2, 30);
        compare(l.sides.top[1].x1, 30);
        var m = line("right", { right: [1070, 1090] });
        compare(m.sides.right[0].y2, 1050);
        compare(m.sides.right[1].y1, 1050);
    }
}

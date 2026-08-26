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

    function frame(position, thickness, radius) {
        return Geometry.frameGeometry(1920, 1080, inset(position), thickness, radius);
    }

    // The band never covers the bar's own strip: the outer rectangle starts
    // where the strip ends.
    function test_the_outer_rectangle_is_the_output_less_the_bar() {
        var g = frame("top", 10, 20);
        compare(JSON.stringify(g.outer), JSON.stringify({ x: 0, y: 40, width: 1920, height: 1040 }));
        compare(JSON.stringify(frame("left", 10, 20).outer), JSON.stringify({ x: 40, y: 0, width: 1880, height: 1080 }));
    }

    // The cut-out is the band in from every edge but the bar's, where it
    // is flush against the strip.
    function test_the_cut_out_is_flush_against_the_bar() {
        var g = frame("top", 10, 20);
        compare(JSON.stringify(g.inner), JSON.stringify({ x: 10, y: 40, width: 1900, height: 1030 }));
        var l = frame("left", 10, 20);
        compare(JSON.stringify(l.inner), JSON.stringify({ x: 40, y: 10, width: 1870, height: 1060 }));
        compare(g.radius, 20);
    }

    function test_a_radius_too_big_for_the_cut_out_is_capped() {
        compare(Geometry.frameGeometry(100, 60, inset("top"), 10, 500).radius, 5);
        compare(frame("top", 10, -4).radius, 0);
    }

    function test_no_thickness_leaves_only_the_cut_out_flush_with_the_edges() {
        var g = frame("top", 0, 20);
        compare(JSON.stringify(g.inner), JSON.stringify(g.outer));
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
}

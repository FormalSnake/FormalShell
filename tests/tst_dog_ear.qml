import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Dog-ear fold-mark regression guard (shell/Components/DogEar.qml,
// DESIGN.md §2 item 7): one right triangle, legs `Theme.space.lg` long,
// painted `foregroundFaint` into the Canvas item's default Canvas.Image
// (software, readback-capable) buffer at a card's top-left corner.
// Replaces tst_corner_marks.qml — CornerMarks' four squares are gone.
TestCase {
    id: testCase
    name: "DogEar"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component {
        id: markComponent

        DogEar {
            width: 40
            height: 30
        }
    }

    function settle(item) {
        waitForRendering(item);
        wait(50);
    }

    // Theme.color's members are plain hex strings (a `var` map, not typed
    // `color` properties), so `.r`/`.g`/`.b` are only meaningful once
    // funneled through an actual `color`-typed property — exactly what
    // DogEar's own `inkColor` does before handing it to the Canvas.
    property color _inkProbe: Theme.color.foregroundFaint

    function _pixel(canvas, x, y) {
        var data = canvas.getContext("2d").getImageData(x, y, 1, 1).data;
        return [data[0], data[1], data[2], data[3]];
    }

    // The Canvas is the one direct child exposing getContext.
    function _findCanvas(item) {
        for (var i = 0; i < item.children.length; i++) {
            var c = item.children[i];
            if (c.getContext !== undefined)
                return c;
        }
        return null;
    }

    function test_mark_exists_as_a_canvas_child() {
        var mark = createTemporaryObject(markComponent, testCase);
        verify(mark);
        settle(mark);

        verify(_findCanvas(mark));
    }

    function test_triangle_fills_the_top_left_corner_with_foreground_faint_ink() {
        var mark = createTemporaryObject(markComponent, testCase);
        verify(mark);
        settle(mark);

        var canvas = _findCanvas(mark);
        var ink = testCase._inkProbe;
        var inkRgb = [Math.round(ink.r * 255), Math.round(ink.g * 255), Math.round(ink.b * 255)];

        var corner = _pixel(canvas, 0, 0);
        compare(corner[0], inkRgb[0]);
        compare(corner[1], inkRgb[1]);
        compare(corner[2], inkRgb[2]);
        compare(corner[3], 255);
    }

    function test_repaints_when_theme_color_changes() {
        var mark = createTemporaryObject(markComponent, testCase);
        verify(mark);
        settle(mark);

        var canvas = _findCanvas(mark);
        var original = Theme.color;
        Theme.color = Object.assign({}, original, { foregroundFaint: "#ff0000" });
        settle(mark);

        var corner = _pixel(canvas, 0, 0);
        compare(corner[0], 255);
        compare(corner[1], 0);
        compare(corner[2], 0);

        Theme.color = original;
    }

    // markSize is Theme.space.lg — 8 at the stub's default scale
    // (fontBaseSize 13) — so both legs reach 8px from the corner point and
    // the hypotenuse falls strictly inside that box. Sampled pixels sit a
    // full pixel back from the diagonal itself (7 is antialiased, since the
    // hypotenuse sweeps through that column within row 0) to avoid asserting
    // on a partial-coverage edge pixel.
    function test_legs_run_lg_sized_along_the_top_and_left_edges() {
        var mark = createTemporaryObject(markComponent, testCase);
        verify(mark);
        settle(mark);

        var canvas = _findCanvas(mark);
        compare(Theme.space.lg, 8);

        // On the top edge, well inside the leg: filled. At the leg's end
        // and past it on that same edge: transparent — the triangle does
        // not run the whole width of the card.
        compare(_pixel(canvas, 6, 0)[3], 255);
        compare(_pixel(canvas, 8, 0)[3], 0);

        // On the left edge, well inside the leg: filled. At its end and
        // past it: transparent.
        compare(_pixel(canvas, 0, 6)[3], 255);
        compare(_pixel(canvas, 0, 8)[3], 0);

        // Deep into the triangle's far corner, well past where the
        // diagonal has already cut in: transparent — this is a triangle,
        // not a square.
        compare(_pixel(canvas, 7, 7)[3], 0);
    }

    function test_other_three_corners_stay_bare() {
        var mark = createTemporaryObject(markComponent, testCase);
        verify(mark);
        settle(mark);

        var canvas = _findCanvas(mark);
        compare(_pixel(canvas, mark.width - 1, 0)[3], 0);
        compare(_pixel(canvas, 0, mark.height - 1)[3], 0);
        compare(_pixel(canvas, mark.width - 1, mark.height - 1)[3], 0);
    }
}

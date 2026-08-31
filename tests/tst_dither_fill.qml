import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Ordered-dither regression guard (shell/Components/DitherFill.qml,
// DESIGN.md §2 item 8): a 2px-period checker of `mutedForeground` on
// transparent, painted once into the Canvas item's default Canvas.Image
// (software, readback-capable) buffer.
TestCase {
    id: testCase
    name: "DitherFill"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component {
        id: fillComponent

        DitherFill {
            width: 20
            height: 10
        }
    }

    Component {
        id: fillWithContentComponent

        DitherFill {
            id: dither
            width: 20
            height: 10

            readonly property Item probeChild: child

            Rectangle {
                id: child
                width: parent.width * 0.5
                height: parent.height
                color: "red"
            }
        }
    }

    function settle(item) {
        waitForRendering(item);
        wait(50);
    }

    // DitherFill's own `inkColor` is already a typed `color` property, so
    // this probe reads the same value it hands to the Canvas.
    property color _inkProbe: Theme.color.mutedForeground

    function _pixel(canvas, x, y) {
        var data = canvas.getContext("2d").getImageData(x, y, 1, 1).data;
        return [data[0], data[1], data[2], data[3]];
    }

    // The Canvas is the one direct child exposing getContext — everything
    // else DitherFill declares (the content overlay Item) does not.
    function _findCanvas(item) {
        for (var i = 0; i < item.children.length; i++) {
            var c = item.children[i];
            if (c.getContext !== undefined)
                return c;
        }
        return null;
    }

    function test_paints_a_two_pixel_period_checker_of_foreground_faint() {
        var dither = createTemporaryObject(fillComponent, testCase);
        verify(dither);
        settle(dither);

        var canvas = _findCanvas(dither);
        verify(canvas);

        var ink = testCase._inkProbe;
        var inkRgb = [Math.round(ink.r * 255), Math.round(ink.g * 255), Math.round(ink.b * 255)];

        var filled = _pixel(canvas, 0, 0);
        compare(filled[0], inkRgb[0]);
        compare(filled[1], inkRgb[1]);
        compare(filled[2], inkRgb[2]);
        compare(filled[3], 255);

        // Same row, next column: the checker's other phase, fully
        // transparent.
        var empty = _pixel(canvas, 1, 0);
        compare(empty[3], 0);

        // Next row: the phase flips, so (1,1) is filled and (0,1) is not —
        // this is what makes it a checker rather than vertical stripes.
        var filledRow1 = _pixel(canvas, 1, 1);
        compare(filledRow1[3], 255);
        var emptyRow1 = _pixel(canvas, 0, 1);
        compare(emptyRow1[3], 0);
    }

    function test_repaints_when_ink_color_changes() {
        var dither = createTemporaryObject(fillComponent, testCase);
        verify(dither);
        settle(dither);

        var canvas = _findCanvas(dither);
        dither.inkColor = "#ff0000";
        settle(dither);

        var filled = _pixel(canvas, 0, 0);
        compare(filled[0], 255);
        compare(filled[1], 0);
        compare(filled[2], 0);
    }

    function test_content_children_size_to_the_fill() {
        var dither = createTemporaryObject(fillWithContentComponent, testCase);
        verify(dither);
        settle(dither);

        compare(dither.probeChild.width, dither.width * 0.5);
        compare(dither.probeChild.height, dither.height);
    }
}

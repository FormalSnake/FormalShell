import QtQuick
import QtTest
import "../shell/Components"

// Cover-palette extraction regression guard (shell/Components/ArtPalette.qml,
// DESIGN.md §2 item 12 / §4 item 8, M20 Task 5b): a Canvas samples a source
// image, posterizes every pixel to the same step count DitherImage's
// "retro" mode paints with, frequency-counts the steps, and exposes the
// six most frequent DISTINCT ones ordered by luminance. `quadSource` below
// is a 4x4 fixture with four equal-frequency 2x2 quadrants (red, lime,
// blue, yellow — verified pixel-by-pixel at fixture-creation time), each
// already sitting on a retro palette step (0/255 only), so the expected
// output is exact and order-checkable by luminance:
// blue (29) < red (76) < lime (150) < yellow (226).
TestCase {
    id: testCase
    name: "ArtPalette"
    width: 200
    height: 200
    visible: true
    when: windowShown

    readonly property string quadSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAEAgMAAADUn3btAAAADFBMVEX/AAAA/wAAAP///wDWAo97AAAAEElEQVQI12NgZWBlWM+wHgADAAFpR/xB6wAAAABJRU5ErkJggg=="
    readonly property string redSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAEAQMAAACTPww9AAAAA1BMVEXIKChQLvxyAAAAC0lEQVQI12NggAAAAAgAAS8g3TEAAAAASUVORK5CYII="

    Component {
        id: paletteComponent
        ArtPalette {}
    }

    function _rgb(c) {
        return [Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)];
    }

    function waitForColors(palette, count) {
        tryVerify(function () { return palette.colors.length === count; }, 3000);
    }

    function test_multi_color_fixture_yields_the_four_distinct_steps_ordered_by_luminance() {
        var palette = createTemporaryObject(paletteComponent, testCase, { source: quadSource });
        verify(palette);
        waitForColors(palette, 4);

        var expected = [
            [0, 0, 255],   // blue, luma 29
            [255, 0, 0],   // red, luma 76
            [0, 255, 0],   // lime, luma 150
            [255, 255, 0]  // yellow, luma 226
        ];
        for (var i = 0; i < expected.length; i++) {
            var got = _rgb(palette.colors[i]);
            compare(got, expected[i]);
        }
    }

    function test_empty_source_yields_an_empty_palette() {
        var palette = createTemporaryObject(paletteComponent, testCase, { source: "" });
        verify(palette);
        wait(50);
        compare(palette.colors.length, 0);
    }

    function test_source_change_recomputes_the_palette() {
        var palette = createTemporaryObject(paletteComponent, testCase, { source: quadSource });
        verify(palette);
        waitForColors(palette, 4);

        // redSource is a solid mid-tone red (rgb(200,40,40)) — ArtPalette's
        // plain nearest-step quantize (no Bayer bias) posterizes it
        // deterministically to a single step, (170,0,0).
        palette.source = redSource;
        tryVerify(function () {
            if (palette.colors.length !== 1)
                return false;
            var got = _rgb(palette.colors[0]);
            return got[0] === 170 && got[1] === 0 && got[2] === 0;
        }, 3000);
    }
}

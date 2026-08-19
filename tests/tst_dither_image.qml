import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Ordered-dither imagery regression guard (shell/Components/DitherImage.qml,
// DESIGN.md §2 item 12): a Canvas draws a hidden source Image, thresholds
// its luminance against a 4x4 Bayer matrix, and paints the duotone with
// per-pixel `fillRect` — `putImageData` was proven (in-VM, real Wayland
// rendering) to silently fail to composite after a `drawImage(Image item)`
// in the same paint, which `fillRect` does not. Fixture sources are inline
// `data:` PNGs (4x4 solid white/black) so the test needs no external file.
// `mode: "retro"` (M20 Task 5b) keeps the source's own colors instead of
// reducing to two role colors: dither.js derives a palette of at most
// `paletteSize` colors from the image itself and each grid cell takes its
// nearest entry, ordered-dithered against its second nearest (2026-08-12 —
// tst_dither_palette.qml covers that engine directly, this file covers what
// it paints). `chunk` (default 2, M21 Task 3) runs the pass on a
// width/chunk x height/chunk grid, each cell painting as one chunk-sized
// hard-edged square.
//
// Two fixtures carry the retro cases, because the two halves of the owner's
// 2026-08-12 report pull in opposite directions: `redishSource` is one solid
// mid-tone color and must come out perfectly flat (no dots on a monotone
// source), while `rampSource` is an 8-step gradient and must come out
// dithered between palette entries (still a dither, not a posterize).
TestCase {
    id: testCase
    name: "DitherImage"
    width: 200
    height: 200
    visible: true
    when: windowShown

    readonly property string whiteSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAEAQAAAACBiqPTAAAADElEQVQI12P4wACGAA8IA8FeW+PBAAAAAElFTkSuQmCC"
    readonly property string blackSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAEAQAAAACBiqPTAAAAC0lEQVQI12NggAAAAAgAAS8g3TEAAAAASUVORK5CYII="
    // Mid-tone red (rgb(200,40,40)), 4x4 solid: the monotone case. A value
    // nowhere near 0 or 255 is exactly what the old fixed posterize grid
    // speckled, and what an image-derived palette must now paint flat.
    readonly property string redishSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAEAQMAAACTPww9AAAAA1BMVEXIKChQLvxyAAAAC0lEQVQI12NggAAAAAgAAS8g3TEAAAAASUVORK5CYII="
    // 8x8, eight full-height columns stepping (0,0,60) -> (28,56,255): more
    // distinct colors than the default 6-color palette can hold, so the pass
    // has to quantize AND dither, and every column is blue-dominant so any
    // entry that drifted off the source's hue is visible.
    readonly property string rampSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAJUlEQVR42mNgYLBh4YjgECjhkZggoLBGROOEhMETGYv/DENLAgDFkjH5v+1GqAAAAABJRU5ErkJggg=="
    // 4x2, four full-height columns: red, green, blue, white. Non-square on
    // purpose, and structured along the axis a cover fit crops, so a
    // stretched draw and a cropped one disagree about every column. Every
    // channel is already 0 or 255, i.e. exactly on a posterize step, so the
    // Bayer bias (+/-0.46875 of a step) cannot tip one and the expected
    // colors are exact.
    readonly property string columnsSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAAGUlEQVQI12P4z8DA8J+BgeH/////mRiQAABryAX9tXK4NwAAAABJRU5ErkJggg=="

    // A source Image the test owns, for the `sourceItem` path.
    Image {
        id: externalImage
        source: testCase.whiteSource
        visible: false
        cache: false
    }

    Component {
        id: imageComponent

        DitherImage {
            width: 20
            height: 20
        }
    }

    function settle(item) {
        waitForRendering(item);
        wait(50);
    }

    property color _lightProbe: Theme.color.background
    property color _darkProbe: Theme.color.foreground

    function _rgb(c) {
        return [Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)];
    }

    function _pixel(canvas, x, y) {
        var data = canvas.getContext("2d").getImageData(x, y, 1, 1).data;
        return [data[0], data[1], data[2], data[3]];
    }

    // The Canvas is the one direct child exposing getContext — the hidden
    // source Image does not.
    function _findCanvas(item) {
        for (var i = 0; i < item.children.length; i++) {
            var c = item.children[i];
            if (c.getContext !== undefined)
                return c;
        }
        return null;
    }

    function waitPainted(canvas, x, y) {
        tryVerify(function () { return _pixel(canvas, x, y)[3] === 255; }, 2000);
    }

    // The hidden source Image can briefly report `Ready` before its decoded
    // pixmap is actually synced for `Canvas.drawImage()` to read (an
    // asynchronous-Image/Canvas timing gap, not a DitherImage logic bug) —
    // a first paint can land on blank (0,0,0,0) source data, which duotone
    // mode reads as "all dark". That looks like a completed paint to
    // `waitPainted`, so mode-mixing tests instead poll for the actual
    // expected pixel, forcing a fresh `requestPaint()` each attempt until
    // the real decode has landed.
    function waitForPixel(canvas, x, y, matches) {
        tryVerify(function () {
            canvas.requestPaint();
            return matches(_pixel(canvas, x, y));
        }, 3000);
    }

    function test_solid_white_source_dithers_to_the_light_role_color() {
        var dither = createTemporaryObject(imageComponent, testCase, { source: whiteSource });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        verify(canvas);
        waitPainted(canvas, 0, 0);

        var light = _rgb(testCase._lightProbe);
        for (var i = 0; i < 3; i++) {
            var px = _pixel(canvas, i * 5, i * 5);
            compare(px[0], light[0]);
            compare(px[1], light[1]);
            compare(px[2], light[2]);
            compare(px[3], 255);
        }
    }

    function test_solid_black_source_dithers_to_the_dark_role_color() {
        var dither = createTemporaryObject(imageComponent, testCase, { source: blackSource });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        verify(canvas);
        waitPainted(canvas, 0, 0);

        var dark = _rgb(testCase._darkProbe);
        for (var i = 0; i < 3; i++) {
            var px = _pixel(canvas, i * 5, i * 5);
            compare(px[0], dark[0]);
            compare(px[1], dark[1]);
            compare(px[2], dark[2]);
            compare(px[3], 255);
        }
    }

    function test_repaints_when_role_colors_change() {
        var dither = createTemporaryObject(imageComponent, testCase, { source: whiteSource });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        waitPainted(canvas, 0, 0);

        dither.lightColor = "#ff0000";
        settle(dither);

        var px = _pixel(canvas, 0, 0);
        compare(px[0], 255);
        compare(px[1], 0);
        compare(px[2], 0);
    }

    function test_mode_defaults_to_duotone() {
        var dither = createTemporaryObject(imageComponent, testCase);
        verify(dither);
        compare(dither.mode, "duotone");
    }

    function test_retro_palette_size_defaults_to_six() {
        var dither = createTemporaryObject(imageComponent, testCase);
        verify(dither);
        compare(dither.paletteSize, 6);
    }

    function test_retro_chunk_defaults_to_two() {
        var dither = createTemporaryObject(imageComponent, testCase);
        verify(dither);
        compare(dither.chunk, 2);
    }

    // THE regression this engine was rewritten for (owner, live shell,
    // 2026-08-12: "its too intense and it adds dots to monotone
    // wallpapers"). A solid source's own color IS the whole derived palette,
    // so every cell matches an entry exactly and nothing dithers: one color
    // over the entire canvas, and it is the source's, not a nearby step.
    function test_retro_mode_paints_a_monotone_source_perfectly_flat() {
        var dither = createTemporaryObject(imageComponent, testCase, { source: redishSource, mode: "retro" });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        verify(canvas);

        waitForPixel(canvas, 0, 0, function (px) { return px[0] > px[1] && px[0] > px[2]; });

        for (var y = 0; y < 20; y += 1) {
            for (var x = 0; x < 20; x += 1) {
                var px = _pixel(canvas, x, y);
                compare(px[0], 200);
                compare(px[1], 40);
                compare(px[2], 40);
                compare(px[3], 255);
            }
        }
    }

    // The other half: a source with more colors than the palette holds is
    // reduced to that palette and dithered between its entries. Distinct
    // colors on screen must not exceed `paletteSize`, and must exceed two —
    // a pass that collapsed the ramp, or one that never quantized it, fails
    // one of those two bounds.
    function test_retro_mode_reduces_a_gradient_to_at_most_palette_size_colors() {
        var dither = createTemporaryObject(imageComponent, testCase, { source: rampSource, mode: "retro" });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        verify(canvas);

        waitForPixel(canvas, 19, 10, function (px) { return px[3] === 255 && px[2] > px[0]; });

        var seen = [];
        for (var y = 0; y < 20; y++) {
            for (var x = 0; x < 20; x++) {
                var px = _pixel(canvas, x, y);
                compare(px[3], 255);
                // Blue-dominant throughout: no entry drifted off the
                // source's own hue on the way through the palette.
                verify(px[2] > px[0]);
                var key = px[0] + "," + px[1] + "," + px[2];
                if (seen.indexOf(key) < 0)
                    seen.push(key);
            }
        }
        verify(seen.length > 2);
        verify(seen.length <= dither.paletteSize);
    }

    // Chunk geometry (M21 Task 3): with the default chunk 2, a 20x20
    // component paints a 10x10 grid of cells, each a hard-edged block of
    // one color rather than anything smooth-scaled. The ramp fixture is the
    // one to check it on — a monotone source would satisfy uniformity
    // trivially — and its cells must not all be the same color either, or
    // the grid collapsed instead of quantizing.
    function test_retro_chunk_paints_uniform_squares_that_vary_by_cell() {
        var dither = createTemporaryObject(imageComponent, testCase, { source: rampSource, mode: "retro" });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        verify(canvas);

        waitForPixel(canvas, 19, 10, function (px) { return px[3] === 255 && px[2] > px[0]; });

        function samePixel(a, b) {
            return a[0] === b[0] && a[1] === b[1] && a[2] === b[2] && a[3] === b[3];
        }

        // Every 2x2 block of the grid is one flat square.
        for (var gy = 0; gy < 10; gy++) {
            for (var gx = 0; gx < 10; gx++) {
                var cell = _pixel(canvas, gx * 2, gy * 2);
                verify(samePixel(_pixel(canvas, gx * 2 + 1, gy * 2), cell));
                verify(samePixel(_pixel(canvas, gx * 2, gy * 2 + 1), cell));
                verify(samePixel(_pixel(canvas, gx * 2 + 1, gy * 2 + 1), cell));
            }
        }

        // ...and the row across the ramp is not one single color.
        verify(!samePixel(_pixel(canvas, 0, 10), _pixel(canvas, 18, 10)));
    }

    // The whole point of retro mode: a red source stays red. Every sampled
    // pixel's R channel must outrank both G and B, never collapsing to a
    // gray (R === G === B) the way duotone mode would.
    function test_retro_mode_preserves_hue_never_grayscale() {
        var dither = createTemporaryObject(imageComponent, testCase, { source: redishSource, mode: "retro" });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        verify(canvas);

        waitForPixel(canvas, 0, 0, function (px) { return px[0] > px[1] && px[0] > px[2]; });

        for (var y = 0; y < 4; y++) {
            for (var x = 0; x < 4; x++) {
                var px = _pixel(canvas, x, y);
                verify(px[0] > px[1]);
                verify(px[0] > px[2]);
            }
        }
    }

    // `painted` is what Background.qml's crossfade gates on: a DitherImage
    // shows nothing at all until its canvas has run, so a fade started on
    // the source Image's own `Ready` would fade in a blank layer.
    function test_painted_reports_whether_the_canvas_has_the_current_source() {
        var dither = createTemporaryObject(imageComponent, testCase);
        verify(dither);
        compare(dither.painted, false);
        settle(dither);

        dither.source = whiteSource;
        var canvas = _findCanvas(dither);
        verify(canvas);
        var light = _rgb(testCase._lightProbe);
        waitForPixel(canvas, 0, 0, function (px) { return px[3] === 255 && px[0] === light[0]; });
        compare(dither.painted, true);

        // Synchronous, so this is observable before the new decode lands.
        dither.source = blackSource;
        compare(dither.painted, false);
    }

    // `sourceItem` takes over from `source` entirely: the wallpaper hands
    // over the Image its own crossfade already keeps loaded rather than
    // paying for a second full-screen decode per layer.
    function test_source_item_supplies_the_pixels_and_source_is_ignored() {
        tryVerify(function () { return externalImage.status === Image.Ready; }, 2000);

        var dither = createTemporaryObject(imageComponent, testCase, {
            source: blackSource,
            sourceItem: externalImage
        });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        verify(canvas);

        // externalImage is the white fixture, so the light role wins; the
        // black `source` would have produced the dark role instead.
        var light = _rgb(testCase._lightProbe);
        waitForPixel(canvas, 0, 0, function (px) { return px[3] === 255 && px[0] === light[0]; });

        var px = _pixel(canvas, 10, 10);
        compare(px[0], light[0]);
        compare(px[1], light[1]);
        compare(px[2], light[2]);
    }

    // Canvas.drawImage reads the decoded pixmap and ignores the source
    // item's fillMode, so the cover crop is computed in the paint pass. The
    // 4x2 fixture scaled to cover a 20x20 box is 40x20, centered, leaving
    // only its two middle columns (green, blue) on screen. A stretched draw
    // would show all four columns at 5px each, putting red at x=2 and white
    // at x=17.
    //
    // Asserted by channel dominance rather than by exact hex: what survives
    // the crop is a claim about geometry, and pinning the palette's own
    // averages here would make an unrelated quantizer change look like a
    // cropping regression.
    function test_non_square_source_is_cover_cropped_never_stretched() {
        var dither = createTemporaryObject(imageComponent, testCase, {
            source: columnsSource,
            mode: "retro"
        });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        verify(canvas);

        waitForPixel(canvas, 2, 10, function (px) { return px[3] === 255 && px[1] > px[0] && px[1] > px[2]; });

        var left = _pixel(canvas, 2, 10);
        verify(left[1] > left[0]);
        verify(left[1] > left[2]);

        var right = _pixel(canvas, 14, 10);
        verify(right[2] > right[0]);
        verify(right[2] > right[1]);

        // Neither cropped-away column may appear anywhere along the row: no
        // red-dominant pixel, and nothing near white.
        for (var x = 0; x < 20; x++) {
            var px = _pixel(canvas, x, 10);
            verify(!(px[0] > px[1] && px[0] > px[2]));
            verify(!(px[0] > 200 && px[1] > 200 && px[2] > 200));
        }
    }

    function test_mode_switch_from_retro_to_duotone_changes_output_for_the_same_source() {
        var dither = createTemporaryObject(imageComponent, testCase, { source: whiteSource, mode: "retro" });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        verify(canvas);

        waitForPixel(canvas, 0, 0, function (px) { return px[3] === 255; });

        dither.mode = "duotone";

        var light = _rgb(testCase._lightProbe);
        waitForPixel(canvas, 0, 0, function (px) { return px[3] === 255 && px[0] === light[0]; });

        var px = _pixel(canvas, 0, 0);
        compare(px[0], light[0]);
        compare(px[1], light[1]);
        compare(px[2], light[2]);
        compare(px[3], 255);
    }
}

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
// `mode: "mask"` (M20 Task 5) swaps the threshold from luminance to alpha:
// RGBA fixtures below cover fully opaque, fully transparent, and a uniform
// mid-alpha source standing in for a soft anti-aliased icon edge.
TestCase {
    id: testCase
    name: "DitherImage"
    width: 200
    height: 200
    visible: true
    when: windowShown

    readonly property string whiteSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAEAQAAAACBiqPTAAAADElEQVQI12P4wACGAA8IA8FeW+PBAAAAAElFTkSuQmCC"
    readonly property string blackSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAEAQAAAACBiqPTAAAAC0lEQVQI12NggAAAAAgAAS8g3TEAAAAASUVORK5CYII="
    // RGBA 4x4 fixtures for mask mode: uniform alpha, arbitrary RGB (mask
    // mode must ignore RGB entirely). Opaque and transparent prove the two
    // decisive ends; the mid-alpha one is the soft anti-aliased-edge case
    // the Bayer bias has to dither into a pure {dark, transparent} stipple.
    readonly property string maskOpaqueSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR42mM4oRH1HxkzkC4AANToJJGdC7PfAAAAAElFTkSuQmCC"
    readonly property string maskTransparentSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR42mM4oRHFgIwZSBcAAM7SFKH0VJcTAAAAAElFTkSuQmCC"
    readonly property string maskSoftEdgeSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR42mPgOiHXgIwZSBcAAAixFwFSLA26AAAAAElFTkSuQmCC"

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
    // mode reads as "all dark" and mask mode reads as "nothing crosses the
    // alpha threshold". Both look like a completed paint to `waitPainted`,
    // so mode-mixing tests instead poll for the actual expected pixel,
    // forcing a fresh `requestPaint()` each attempt until the real decode
    // has landed.
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

    function test_mask_mode_paints_fully_opaque_source_as_dark() {
        var dither = createTemporaryObject(imageComponent, testCase, { source: maskOpaqueSource, mode: "mask" });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        verify(canvas);

        var dark = _rgb(testCase._darkProbe);
        waitForPixel(canvas, 0, 0, function (px) { return px[3] === 255 && px[0] === dark[0]; });

        for (var i = 0; i < 3; i++) {
            var px = _pixel(canvas, i * 5, i * 5);
            compare(px[0], dark[0]);
            compare(px[1], dark[1]);
            compare(px[2], dark[2]);
            compare(px[3], 255);
        }
    }

    function test_mask_mode_clears_a_previously_painted_pixel_when_source_goes_fully_transparent() {
        var dither = createTemporaryObject(imageComponent, testCase, { source: maskOpaqueSource, mode: "mask" });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        verify(canvas);

        var dark = _rgb(testCase._darkProbe);
        waitForPixel(canvas, 0, 0, function (px) { return px[3] === 255 && px[0] === dark[0]; });

        dither.source = maskTransparentSource;
        waitForPixel(canvas, 0, 0, function (px) { return px[3] === 0; });

        var px = _pixel(canvas, 0, 0);
        compare(px[3], 0);
    }

    // The mid-alpha fixture is uniform across its whole source, so the
    // Bayer bias alone decides paint vs. clear per canvas pixel — this is
    // the soft anti-aliased-edge case mask mode exists for. Every sampled
    // pixel must land decisively in {darkColor at alpha 255, transparent},
    // never a blended in-between value. Canvas coordinate (0,0) sits at the
    // Bayer matrix's own lowest threshold cell, so it always paints once the
    // real (non-blank) source has decoded — the anchor `waitForPixel` waits
    // on before the grid scan below.
    function test_soft_edged_alpha_mask_renders_only_dark_color_or_transparent() {
        var dither = createTemporaryObject(imageComponent, testCase, { source: maskSoftEdgeSource, mode: "mask" });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        verify(canvas);

        var dark = _rgb(testCase._darkProbe);
        waitForPixel(canvas, 0, 0, function (px) { return px[3] === 255 && px[0] === dark[0]; });

        var sawPainted = false;
        var sawTransparent = false;
        // Step by 1, not 2: the Bayer tile repeats every 4 pixels, and an
        // even-only stride only ever visits phases {0, 2} mod 4 — exactly
        // the tile's two lowest-threshold cells, which paint at any alpha
        // above ~0.19 regardless of dithering. A full stride is the only
        // way to actually see both outcomes.
        for (var y = 0; y < 4; y++) {
            for (var x = 0; x < 4; x++) {
                var px = _pixel(canvas, x, y);
                if (px[3] === 0) {
                    sawTransparent = true;
                } else {
                    compare(px[3], 255);
                    compare(px[0], dark[0]);
                    compare(px[1], dark[1]);
                    compare(px[2], dark[2]);
                    sawPainted = true;
                }
            }
        }
        verify(sawPainted);
        verify(sawTransparent);
    }

    function test_mode_switch_from_duotone_to_mask_changes_output_for_the_same_source() {
        var dither = createTemporaryObject(imageComponent, testCase, { source: whiteSource, mode: "duotone" });
        verify(dither);
        settle(dither);
        var canvas = _findCanvas(dither);
        verify(canvas);

        var light = _rgb(testCase._lightProbe);
        waitForPixel(canvas, 0, 0, function (px) { return px[3] === 255 && px[0] === light[0]; });

        var duotonePixel = _pixel(canvas, 0, 0);
        compare(duotonePixel[0], light[0]);
        compare(duotonePixel[1], light[1]);
        compare(duotonePixel[2], light[2]);

        dither.mode = "mask";

        var dark = _rgb(testCase._darkProbe);
        waitForPixel(canvas, 0, 0, function (px) { return px[3] === 255 && px[0] === dark[0]; });

        var maskPixel = _pixel(canvas, 0, 0);
        compare(maskPixel[0], dark[0]);
        compare(maskPixel[1], dark[1]);
        compare(maskPixel[2], dark[2]);
        compare(maskPixel[3], 255);
    }
}

import QtQuick
import QtTest
import "../shell/Components/dither.js" as Dither

// The palette engine behind DitherImage's retro pass
// (shell/Components/dither.js, DESIGN.md §2 item 12). Pure functions over
// flat r,g,b cell arrays, so the color math is checkable without a Canvas —
// tst_dither_image.qml covers the same engine as it actually paints.
//
// The regression these tests exist for (owner, live shell, 2026-08-12): the
// pass used to posterize each channel onto a fixed grid of evenly-spaced
// steps, so a flat region sitting near one of those step boundaries dithered
// forever ("it adds dots to monotone wallpapers") and every dot mixed two
// colors a full step apart ("its too intense"). A palette derived from the
// image cannot do either: the image's own colors ARE the palette, so a flat
// region has nothing to mix with, and neighboring entries are as far apart
// as the image's own colors are, never further.
TestCase {
    name: "DitherPalette"

    function _cells(colors) {
        var out = [];
        colors.forEach(function (c) { out.push(c[0], c[1], c[2]); });
        return out;
    }

    function _entries(pal) {
        var out = [];
        for (var i = 0; i < pal.length; i += 3)
            out.push([pal[i], pal[i + 1], pal[i + 2]]);
        return out;
    }

    // THE monotone guard: one color in, one color out, exactly — not a
    // nearby step, and not two steps mixed.
    function test_a_solid_source_yields_its_own_single_color() {
        var cells = _cells([[142, 68, 173], [142, 68, 173], [142, 68, 173], [142, 68, 173]]);
        var pal = Dither.palette(cells, 4, 6);
        compare(pal.length, 3);
        compare(pal[0], 142);
        compare(pal[1], 68);
        compare(pal[2], 173);
    }

    // ...and nothing dithers against it, at any grid position: every cell
    // takes the one entry, so a monotone wallpaper paints flat.
    function test_a_solid_source_never_dithers() {
        var count = 64;
        var colors = [];
        for (var i = 0; i < count; i++)
            colors.push([142, 68, 173]);
        var cells = _cells(colors);
        var pal = Dither.palette(cells, count, 6);
        var indices = Dither.quantize(cells, count, 8, pal);
        for (var k = 0; k < count; k++)
            compare(indices[k], 0);
    }

    // A source with fewer distinct colors than the palette allows gets a
    // shorter palette, not padding: duplicate entries would be two names for
    // one color, and quantize() would then have a "second nearest" at zero
    // distance to dither against for no reason.
    function test_palette_never_invents_entries_the_source_lacks() {
        var cells = _cells([[0, 0, 0], [255, 255, 255], [0, 0, 0], [255, 255, 255]]);
        var pal = Dither.palette(cells, 4, 6);
        compare(pal.length, 6);
        var entries = _entries(pal);
        // Order is the median cut's own, so check membership rather than
        // position.
        var hexes = entries.map(function (e) { return Dither.hex(e[0], e[1], e[2]); });
        verify(hexes.indexOf("#000000") >= 0);
        verify(hexes.indexOf("#ffffff") >= 0);
    }

    function test_palette_is_capped_at_max_colors() {
        var colors = [];
        for (var i = 0; i < 64; i++)
            colors.push([i * 4, 255 - i * 3, (i * 7) % 256]);
        var pal = Dither.palette(_cells(colors), 64, 6);
        compare(pal.length, 18);
    }

    function test_empty_input_yields_no_palette() {
        compare(Dither.palette([], 0, 6).length, 0);
        compare(Dither.quantize([], 0, 1, []).length, 0);
    }

    // The dither itself: a cell exactly between two entries lands on a 50/50
    // Bayer checker (half the grid positions take each), which is the correct
    // ordered dither and the densest pattern the engine can produce.
    function test_a_color_midway_between_two_entries_checkers() {
        var pal = [0, 0, 0, 100, 100, 100];
        var count = 16;
        var cells = [];
        for (var i = 0; i < count; i++)
            cells.push(50, 50, 50);
        var indices = Dither.quantize(cells, count, 4, pal);
        var second = 0;
        for (var k = 0; k < count; k++)
            second += indices[k] === 1 ? 1 : 0;
        compare(second, 8);
    }

    // A cell a quarter of the way between two entries takes the far one a
    // quarter of the time, so a gradient averages back to the color the
    // source actually had instead of banding.
    function test_dither_density_tracks_the_distance_between_entries() {
        var pal = [0, 0, 0, 100, 100, 100];
        var count = 16;
        var cells = [];
        for (var i = 0; i < count; i++)
            cells.push(25, 25, 25);
        var indices = Dither.quantize(cells, count, 4, pal);
        var second = 0;
        for (var k = 0; k < count; k++)
            second += indices[k] === 1 ? 1 : 0;
        compare(second, 4);
    }

    // An exact palette match short-circuits regardless of neighbors: this is
    // what keeps a flat region of a color the palette holds free of dots even
    // when the image also contains a gradient that put entries nearby.
    function test_an_exact_match_never_takes_the_second_nearest() {
        var pal = [0, 0, 0, 10, 10, 10, 200, 200, 200];
        var count = 16;
        var cells = [];
        for (var i = 0; i < count; i++)
            cells.push(10, 10, 10);
        var indices = Dither.quantize(cells, count, 4, pal);
        for (var k = 0; k < count; k++)
            compare(indices[k], 1);
    }

    // Hue cannot drift to something the source never held: entries are
    // averages of the source's own colors, so a blue ramp quantizes to blue
    // entries. This is also why a dithered wallpaper can't feed matugen a
    // color the file doesn't contain — though it never feeds it anything at
    // all, since ThemeEngine reads the file.
    function test_entries_stay_inside_the_sources_own_hue() {
        var colors = [];
        for (var i = 0; i < 32; i++)
            colors.push([i, i * 2, 60 + i * 6]);
        var pal = Dither.palette(_cells(colors), 32, 6);
        var entries = _entries(pal);
        verify(entries.length > 1);
        entries.forEach(function (e) {
            verify(e[2] > e[1]);
            verify(e[1] >= e[0]);
        });
    }

    function test_hex_pads_single_digit_channels() {
        compare(Dither.hex(0, 0, 0), "#000000");
        compare(Dither.hex(1, 15, 255), "#010fff");
        compare(Dither.hexPalette([0, 0, 0, 255, 255, 255]).length, 2);
        compare(Dither.hexPalette([0, 0, 0, 255, 255, 255])[1], "#ffffff");
    }

    function test_bayer_matrix_covers_every_threshold_once() {
        compare(Dither.BAYER.length, 16);
        var seen = [];
        Dither.BAYER.forEach(function (v) {
            verify(seen.indexOf(v) < 0);
            seen.push(v);
        });
        compare(seen.length, 16);
    }
}

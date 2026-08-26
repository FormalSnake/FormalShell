import QtQuick
import QtTest
import "../shell/Screensaver/blocks.js" as Blocks

// The block-element geometry the screensaver paints instead of glyphs. Every
// claim here is about a fraction of one cell, so it holds at any font size
// and under any installed monospace face, which is the whole point of the
// table: the banner's solidity stops depending on whether the font's own
// U+2588 happens to fill its advance box (Geist Mono's does not).
TestCase {
    name: "ScreensaverBlocks"

    // The bundled banner's entire alphabet (branding/screensaver.txt), so a
    // table that ever lost one of these fails here rather than in a
    // screenshot nobody reads closely.
    readonly property var bannerCodes: [0x2580, 0x2584, 0x2588]

    function _area(rects) {
        var total = 0;
        for (var i = 0; i < rects.length; i++)
            total += rects[i].w * rects[i].h;
        return total;
    }

    function test_full_block_is_the_whole_cell() {
        var rects = Blocks.rectsFor(0x2588);
        compare(rects.length, 1);
        compare(rects[0].x, 0);
        compare(rects[0].y, 0);
        compare(rects[0].w, 1);
        compare(rects[0].h, 1);
        compare(rects[0].alpha, 1);
        verify(Blocks.isFullCell(rects));
    }

    function test_half_blocks_take_their_named_half() {
        var upper = Blocks.rectsFor(0x2580);
        compare(upper.length, 1);
        compare(upper[0].y, 0);
        compare(upper[0].h, 0.5);
        compare(upper[0].w, 1);
        var lower = Blocks.rectsFor(0x2584);
        compare(lower[0].y, 0.5);
        compare(lower[0].h, 0.5);
        var left = Blocks.rectsFor(0x258C);
        compare(left[0].x, 0);
        compare(left[0].w, 0.5);
        compare(left[0].h, 1);
        var right = Blocks.rectsFor(0x2590);
        compare(right[0].x, 0.5);
        compare(right[0].w, 0.5);
    }

    // The banner stacks these two directly on top of each other, so between
    // them they have to be the cell exactly: any slack is the stripe the
    // owner reported.
    function test_upper_and_lower_half_tile_the_cell() {
        var upper = Blocks.rectsFor(0x2580)[0];
        var lower = Blocks.rectsFor(0x2584)[0];
        compare(upper.y + upper.h, lower.y);
        compare(lower.y + lower.h, 1);
        compare(Blocks.coverage(0x2580) + Blocks.coverage(0x2584), 1);
    }

    function test_lower_eighth_blocks_grow_upward_from_the_bottom() {
        for (var n = 1; n <= 7; n++) {
            var rects = Blocks.rectsFor(0x2580 + n);
            compare(rects.length, 1);
            compare(rects[0].x, 0);
            compare(rects[0].w, 1);
            compare(rects[0].y + rects[0].h, 1);
            fuzzyCompare(rects[0].h, n / 8, 1e-9);
        }
    }

    function test_left_eighth_blocks_shrink_from_the_left_edge() {
        for (var m = 1; m <= 7; m++) {
            var rects = Blocks.rectsFor(0x2588 + m);
            compare(rects.length, 1);
            compare(rects[0].x, 0);
            compare(rects[0].y, 0);
            compare(rects[0].h, 1);
            fuzzyCompare(rects[0].w, (8 - m) / 8, 1e-9);
        }
        fuzzyCompare(Blocks.rectsFor(0x2594)[0].h, 1 / 8, 1e-9);   // upper one eighth
        compare(Blocks.rectsFor(0x2594)[0].y, 0);
        fuzzyCompare(Blocks.rectsFor(0x2595)[0].w, 1 / 8, 1e-9);   // right one eighth
        fuzzyCompare(Blocks.rectsFor(0x2595)[0].x, 7 / 8, 1e-9);
    }

    function test_quadrants_cover_their_named_corners() {
        var cases = [
            { code: 0x2596, quarters: 1 }, { code: 0x2597, quarters: 1 },
            { code: 0x2598, quarters: 1 }, { code: 0x2599, quarters: 3 },
            { code: 0x259A, quarters: 2 }, { code: 0x259B, quarters: 3 },
            { code: 0x259C, quarters: 3 }, { code: 0x259D, quarters: 1 },
            { code: 0x259E, quarters: 2 }, { code: 0x259F, quarters: 3 }
        ];
        for (var i = 0; i < cases.length; i++)
            fuzzyCompare(Blocks.coverage(cases[i].code), cases[i].quarters / 4, 1e-9);
        // Lower left, so the rect sits in the bottom-left corner and nowhere
        // else.
        var ll = Blocks.rectsFor(0x2596);
        compare(ll.length, 1);
        compare(ll[0].x, 0);
        compare(ll[0].y, 0.5);
        // Two quadrants sharing a full edge merge into one rect rather than
        // meeting on a fractional pixel boundary.
        compare(Blocks.rectsFor(0x259B).length, 2);
        compare(Blocks.rectsFor(0x259B)[0].w, 1);
        // A diagonal pair has no shared edge to merge on.
        compare(Blocks.rectsFor(0x259A).length, 2);
    }

    function test_shades_are_one_full_cell_rect_at_their_own_coverage() {
        var shades = [{ code: 0x2591, alpha: 0.25 }, { code: 0x2592, alpha: 0.5 }, { code: 0x2593, alpha: 0.75 }];
        for (var i = 0; i < shades.length; i++) {
            var rects = Blocks.rectsFor(shades[i].code);
            compare(rects.length, 1);
            compare(rects[0].w, 1);
            compare(rects[0].h, 1);
            compare(rects[0].alpha, shades[i].alpha);
            verify(!Blocks.isFullCell(rects));
            compare(Blocks.coverage(shades[i].code), shades[i].alpha);
        }
    }

    // Every entry has to stay inside its own cell and never paint the same
    // pixel twice: an overlapping pair would darken under a translucent draw,
    // an oversized one would bleed into the neighbouring column.
    function test_every_entry_stays_inside_one_cell_without_overlapping() {
        for (var code = 0x2580; code <= 0x259F; code++) {
            var rects = Blocks.rectsFor(code);
            verify(rects !== null);
            verify(rects.length > 0);
            for (var i = 0; i < rects.length; i++) {
                verify(rects[i].x >= 0);
                verify(rects[i].y >= 0);
                verify(rects[i].w > 0);
                verify(rects[i].h > 0);
                verify(rects[i].x + rects[i].w <= 1 + 1e-9);
                verify(rects[i].y + rects[i].h <= 1 + 1e-9);
                verify(rects[i].alpha > 0 && rects[i].alpha <= 1);
                for (var j = i + 1; j < rects.length; j++) {
                    var overlapX = Math.min(rects[i].x + rects[i].w, rects[j].x + rects[j].w) - Math.max(rects[i].x, rects[j].x);
                    var overlapY = Math.min(rects[i].y + rects[i].h, rects[j].y + rects[j].h) - Math.max(rects[i].y, rects[j].y);
                    verify(overlapX <= 1e-9 || overlapY <= 1e-9);
                }
            }
            verify(_area(rects) <= 1 + 1e-9);
        }
    }

    function test_the_bundled_banners_own_characters_are_all_tabled() {
        for (var i = 0; i < bannerCodes.length; i++)
            verify(Blocks.rectsFor(bannerCodes[i]) !== null);
    }

    // Anything outside the block-elements range keeps the font's glyph. The
    // list is what a survey of all 37 ttfx effects turned up outside it: box
    // drawing (synthgrid's grid, decrypt's scramble charset), the circles
    // blackhole collapses through, and matrix's halfwidth katakana. Every one
    // of those is a line or a shape, not a fill that has to meet its
    // neighbour, so painting it as a rectangle would be a lie.
    function test_non_block_codepoints_fall_through_to_the_font() {
        var outside = [0x20, 0x41, 0x30, 0x2f, 0x2500, 0x2502, 0x257f, 0x25a0, 0x25cf, 0x25e6, 0xff71];
        for (var i = 0; i < outside.length; i++) {
            compare(Blocks.rectsFor(outside[i]), null);
            compare(Blocks.coverage(outside[i]), 0);
        }
        verify(!Blocks.isFullCell(null));
    }
}

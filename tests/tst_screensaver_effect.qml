import QtQuick
import QtTest
import "../shell/Screensaver/effect.js" as Effect

TestCase {
    name: "ScreensaverEffect"

    property var banner: Effect.parseBanner("FS\nOK")

    // parseBanner

    function test_parse_banner_pads_short_rows_to_widest_row() {
        var b = Effect.parseBanner("AB\nC");
        compare(b.width, 2);
        compare(b.height, 2);
        compare(b.rows[1], "C ");
    }

    function test_parse_banner_trims_one_trailing_newline() {
        var b = Effect.parseBanner("AB\n");
        compare(b.height, 1);
        compare(b.rows[0], "AB");
    }

    function test_target_char_out_of_bounds_is_space() {
        compare(Effect.targetChar(banner, -1, 0), " ");
        compare(Effect.targetChar(banner, 0, 99), " ");
    }

    // registry

    function test_known_effect_names_are_exactly_five() {
        compare(Effect.EFFECT_NAMES.length, 5);
        var seen = {};
        for (var i = 0; i < Effect.EFFECT_NAMES.length; i++) {
            verify(Effect.isKnownEffect(Effect.EFFECT_NAMES[i]));
            verify(!seen[Effect.EFFECT_NAMES[i]]);
            seen[Effect.EFFECT_NAMES[i]] = true;
        }
    }

    function test_resolve_effect_name_passes_through_known_names() {
        for (var i = 0; i < Effect.EFFECT_NAMES.length; i++)
            compare(Effect.resolveEffectName(Effect.EFFECT_NAMES[i], 0), Effect.EFFECT_NAMES[i]);
    }

    function test_resolve_effect_name_falls_back_for_random_and_unknown() {
        verify(Effect.isKnownEffect(Effect.resolveEffectName("random", 3)));
        verify(Effect.isKnownEffect(Effect.resolveEffectName("not-a-real-effect", 5)));
    }

    function test_resolve_effect_name_is_deterministic_per_seed() {
        compare(Effect.resolveEffectName("random", 17), Effect.resolveEffectName("random", 17));
    }

    // frameState: shape + bounds, generically over every effect

    function test_frame_state_has_exact_row_and_column_counts() {
        for (var i = 0; i < Effect.EFFECT_NAMES.length; i++) {
            var grid = Effect.frameState(Effect.EFFECT_NAMES[i], 5, banner);
            compare(grid.length, banner.height);
            for (var r = 0; r < grid.length; r++)
                compare(grid[r].length, banner.width);
        }
    }

    function test_frame_state_is_deterministic_for_same_inputs() {
        for (var i = 0; i < Effect.EFFECT_NAMES.length; i++) {
            var a = Effect.frameState(Effect.EFFECT_NAMES[i], 12, banner);
            var b = Effect.frameState(Effect.EFFECT_NAMES[i], 12, banner);
            compare(JSON.stringify(a), JSON.stringify(b));
        }
    }

    function test_opacity_always_within_0_and_1_and_char_is_single_char() {
        for (var i = 0; i < Effect.EFFECT_NAMES.length; i++) {
            var name = Effect.EFFECT_NAMES[i];
            for (var frame = 0; frame < 60; frame += 3) {
                var grid = Effect.frameState(name, frame, banner);
                for (var r = 0; r < grid.length; r++) {
                    for (var c = 0; c < grid[r].length; c++) {
                        var cell = grid[r][c];
                        verify(cell.opacity >= 0 && cell.opacity <= 1);
                        compare(cell.char.length, 1);
                    }
                }
            }
        }
    }

    function test_space_target_cells_never_draw_anything() {
        // banner has a real space between "FS" and "OK" at column-major
        // position (2, *) once padded to width 2 there's no shared blank
        // column, so build one explicitly with a guaranteed gap.
        var spaced = Effect.parseBanner("A B");
        for (var i = 0; i < Effect.EFFECT_NAMES.length; i++) {
            var name = Effect.EFFECT_NAMES[i];
            for (var frame = 0; frame < 80; frame += 5) {
                var grid = Effect.frameState(name, frame, spaced);
                compare(grid[0][1].char, " ");
                compare(grid[0][1].opacity, 0);
            }
        }
    }

    // convergence — every effect must actually reach the finished banner,
    // and hold it (no un-converging on later frames).

    function test_every_effect_converges_and_holds() {
        for (var i = 0; i < Effect.EFFECT_NAMES.length; i++) {
            var name = Effect.EFFECT_NAMES[i];
            var atFrame = Effect.convergenceFrame(name, banner);
            for (var extra = 0; extra < 10; extra++) {
                var grid = Effect.frameState(name, atFrame + extra, banner);
                for (var r = 0; r < grid.length; r++) {
                    for (var c = 0; c < grid[r].length; c++) {
                        var expected = Effect.targetChar(banner, c, r);
                        compare(grid[r][c].char, expected);
                        compare(grid[r][c].opacity, expected === " " ? 0 : 1);
                    }
                }
            }
        }
    }

    // convergence must not be instant — each effect actually animates for a
    // real stretch first, i.e. at frame 0 at least one non-space cell is
    // not yet showing its target character.

    function test_every_effect_starts_unconverged() {
        for (var i = 0; i < Effect.EFFECT_NAMES.length; i++) {
            var name = Effect.EFFECT_NAMES[i];
            var grid = Effect.frameState(name, 0, banner);
            var anyUnresolved = false;
            for (var r = 0; r < grid.length && !anyUnresolved; r++) {
                for (var c = 0; c < grid[r].length; c++) {
                    var target = Effect.targetChar(banner, c, r);
                    if (target !== " " && grid[r][c].char !== target) {
                        anyUnresolved = true;
                        break;
                    }
                }
            }
            verify(anyUnresolved, name + " should not already be fully converged at frame 0");
        }
    }

    // decrypt specifics: noise glyph changes frame to frame before reveal

    function test_decrypt_noise_glyph_changes_across_frames_before_reveal() {
        var b = Effect.parseBanner("XXXXXXXXXX");
        var c1 = Effect.frameState("decrypt", 0, b)[0][0].char;
        var c2 = Effect.frameState("decrypt", 1, b)[0][0].char;
        // Not guaranteed different for every single cell/frame pair, but
        // across the whole first row at least one must change.
        var changed = false;
        var row0a = Effect.frameState("decrypt", 0, b)[0];
        var row0b = Effect.frameState("decrypt", 1, b)[0];
        for (var i = 0; i < row0a.length; i++) {
            if (row0a[i].opacity < 1 && row0a[i].char !== row0b[i].char) {
                changed = true;
                break;
            }
        }
        verify(changed);
    }

    // rain specifics: a cell settles (locks) and never reverts to noise or blank

    function test_rain_cell_never_reverts_after_settling() {
        var col = 0, row = banner.height - 1;
        var settledFrame = -1;
        for (var frame = 0; frame < 40; frame++) {
            var cell = Effect.frameState("rain", frame, banner)[row][col];
            var target = Effect.targetChar(banner, col, row);
            if (target === " ") continue;
            if (cell.char === target && cell.opacity === 1) {
                settledFrame = frame;
                break;
            }
        }
        verify(settledFrame >= 0);
        for (var f2 = settledFrame; f2 < settledFrame + 20; f2++) {
            var cell2 = Effect.frameState("rain", f2, banner)[row][col];
            compare(cell2.char, Effect.targetChar(banner, col, row));
            compare(cell2.opacity, 1);
        }
    }

    // expand specifics: the centre cell (or one of the nearest) opens no
    // later than a cell at the banner's corner.

    function test_expand_centre_opens_before_or_with_corner() {
        var big = Effect.parseBanner("XXXXXXXXX\nXXXXXXXXX\nXXXXXXXXX\nXXXXXXXXX\nXXXXXXXXX");
        var cx = Math.floor((big.width - 1) / 2);
        var cy = Math.floor((big.height - 1) / 2);
        var centreRevealFrame = -1;
        var cornerRevealFrame = -1;
        for (var frame = 0; frame < 60; frame++) {
            var grid = Effect.frameState("expand", frame, big);
            if (centreRevealFrame < 0 && grid[cy][cx].opacity > 0) centreRevealFrame = frame;
            if (cornerRevealFrame < 0 && grid[0][0].opacity > 0) cornerRevealFrame = frame;
        }
        verify(centreRevealFrame >= 0);
        verify(cornerRevealFrame >= 0);
        verify(centreRevealFrame <= cornerRevealFrame);
    }

    // slide specifics: even and odd rows sweep in opposite column order.

    function test_slide_alternates_direction_by_row_parity() {
        var wide = Effect.parseBanner("XXXXXXXXXX\nXXXXXXXXXX");
        // Row 0 (even, from-left): column 0 must reveal no later than the
        // last column. Row 1 (odd, from-right): the last column must
        // reveal no later than column 0 — the opposite order.
        function revealFrameOf(row, col) {
            for (var frame = 0; frame < 60; frame++) {
                if (Effect.frameState("slide", frame, wide)[row][col].opacity > 0)
                    return frame;
            }
            return -1;
        }
        var lastCol = wide.width - 1;
        verify(revealFrameOf(0, 0) <= revealFrameOf(0, lastCol));
        verify(revealFrameOf(1, lastCol) <= revealFrameOf(1, 0));
    }

    // scatter specifics: cells arrive at scattered (non-uniform) frames,
    // not all at once, and never show unrelated noise glyphs (only blank
    // or their own target character).

    function test_scatter_cells_arrive_at_varied_frames_and_only_show_target_or_blank() {
        var wide = Effect.parseBanner("ABCDEFGHIJ");
        var arrivals = {};
        for (var frame = 0; frame < Effect.convergenceFrame("scatter", wide); frame++) {
            var row = Effect.frameState("scatter", frame, wide)[0];
            for (var c = 0; c < row.length; c++) {
                var target = Effect.targetChar(wide, c, 0);
                verify(row[c].char === " " || row[c].char === target);
                if (row[c].opacity === 1 && arrivals[c] === undefined)
                    arrivals[c] = frame;
            }
        }
        var distinctFrames = {};
        for (var key in arrivals) distinctFrames[arrivals[key]] = true;
        verify(Object.keys(distinctFrames).length > 1);
    }
}

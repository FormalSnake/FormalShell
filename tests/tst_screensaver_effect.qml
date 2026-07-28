import QtQuick
import QtTest
import "../shell/Screensaver/effect.js" as Effect

TestCase {
    name: "ScreensaverEffect"

    // determinism

    function test_frame_state_is_deterministic_for_same_inputs() {
        var a = Effect.frameState(6, 10, 42);
        var b = Effect.frameState(6, 10, 42);
        compare(JSON.stringify(a), JSON.stringify(b));
    }

    function test_column_state_is_deterministic_for_same_inputs() {
        compare(JSON.stringify(Effect.columnState(2, 17, 20)), JSON.stringify(Effect.columnState(2, 17, 20)));
    }

    // bounds — no out-of-range column/row, no out-of-charset glyph

    function test_frame_state_has_exact_column_and_row_counts() {
        var grid = Effect.frameState(5, 8, 100);
        compare(grid.length, 5);
        for (var c = 0; c < grid.length; c++)
            compare(grid[c].length, 8);
    }

    function test_glyph_always_within_charset() {
        for (var frame = 0; frame < 50; frame++) {
            for (var col = 0; col < 4; col++) {
                for (var row = 0; row < 6; row++) {
                    var ch = Effect.glyphAt(col, row, frame);
                    verify(Effect.CHARSET.indexOf(ch) >= 0);
                }
            }
        }
    }

    function test_brightness_always_within_0_and_1() {
        for (var frame = 0; frame < 60; frame++) {
            for (var col = 0; col < 4; col++) {
                for (var row = 0; row < 10; row++) {
                    var b = Effect.brightnessAt(col, row, frame, 10);
                    verify(b >= 0 && b <= 1);
                }
            }
        }
    }

    function test_head_row_is_always_a_finite_number() {
        for (var frame = 0; frame < 40; frame++) {
            for (var col = 0; col < 5; col++) {
                verify(isFinite(Effect.headRow(col, frame, 10)));
            }
        }
    }

    // decay reaching a resting state

    function test_decay_reaches_and_holds_a_resting_state() {
        // Row 0 with a rowCount comfortably larger than TRAIL_LENGTH: its
        // peak lands early in the cycle, leaving enough runway for the
        // decay to fully complete before the head wraps back to the top —
        // a row near the bottom of a short grid can have its own decay cut
        // short by the wrap instead, which is a separate (and fine) edge
        // case, not what this test is checking.
        var column = 0;
        var row = 0;
        var rowCount = 20;
        var cycle = rowCount + Effect.TRAIL_LENGTH;
        var sawPeak = false;
        var samples = [];
        for (var frame = 0; frame < cycle; frame++) {
            var b = Effect.brightnessAt(column, row, frame, rowCount);
            samples.push(b);
            if (b === 1) sawPeak = true;
        }
        verify(sawPeak);
        // The last few frames of a full cycle must already be resting
        // (fully decayed), not still fading, well before the head could
        // plausibly wrap back around to this row.
        for (var i = cycle - 5; i < cycle; i++)
            compare(samples[i], 0);
    }

    function test_brightness_decays_monotonically_behind_the_head() {
        var column = 1;
        var rowCount = 12;
        var frame = 0;
        var head = Effect.headRow(column, frame, rowCount);
        var prev = 2; // above the valid [0,1] range so the first compare always passes
        var checked = 0;
        for (var behind = 0; behind <= Effect.TRAIL_LENGTH; behind++) {
            var row = head - behind;
            var b = Effect.brightnessAt(column, row, frame, rowCount);
            verify(b <= prev);
            prev = b;
            checked++;
        }
        compare(checked, Effect.TRAIL_LENGTH + 1);
    }
}

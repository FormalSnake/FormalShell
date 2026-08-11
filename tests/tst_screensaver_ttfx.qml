import QtQuick
import QtTest
import "../shell/Screensaver/ttfx.js" as Ttfx

// The ttfx wire protocol, pinned against real ttfx 0.3.0 output: the argv
// the screensaver spawns, the delimiter it splits stdout on, and the parse
// of one frame. The sample streams below are byte-for-byte what the binary
// emits (`ttfx --canvas-width 12 --canvas-height 4 --anchor-canvas c
// --anchor-text c --frame-rate 0 --ignore-terminal-dimensions expand`), so a
// change in either direction fails here rather than in a smoke run.
TestCase {
    name: "ScreensaverTtfx"

    readonly property string esc: "\u001b"

    // registry

    function test_effect_names_are_ttfx_0_3_0s_thirty_seven() {
        compare(Ttfx.EFFECT_NAMES.length, 37);
        var seen = {};
        for (var i = 0; i < Ttfx.EFFECT_NAMES.length; i++) {
            verify(Ttfx.isKnownEffect(Ttfx.EFFECT_NAMES[i]));
            verify(!seen[Ttfx.EFFECT_NAMES[i]]);
            seen[Ttfx.EFFECT_NAMES[i]] = true;
        }
        verify(!Ttfx.isKnownEffect("scatter")); // effect.js's name, not ttfx's
        verify(Ttfx.isKnownEffect("scattered"));
    }

    function test_timed_effects_are_the_two_wall_clock_gated_ones() {
        verify(Ttfx.isTimedEffect("matrix"));
        verify(Ttfx.isTimedEffect("thunderstorm"));
        verify(!Ttfx.isTimedEffect("decrypt"));
    }

    function test_reroll_replays_a_pinned_effect() {
        for (var i = 0; i < Ttfx.EFFECT_NAMES.length; i++)
            compare(Ttfx.rerollEffectName(Ttfx.EFFECT_NAMES[i], "beams", 7), Ttfx.EFFECT_NAMES[i]);
    }

    function test_reroll_never_repeats_the_previous_effect() {
        for (var seed = 0; seed < 80; seed++)
            verify(Ttfx.rerollEffectName("random", "decrypt", seed) !== "decrypt");
    }

    function test_reroll_of_an_unknown_name_falls_back_to_random() {
        var picked = Ttfx.rerollEffectName("nonesuch", "", 3);
        verify(Ttfx.isKnownEffect(picked));
    }

    // argv

    function test_args_carry_the_canvas_and_the_effect_last() {
        var args = Ttfx.args({
            bannerPath: "/banner.txt", columns: 96, rows: 30, effect: "decrypt",
            frameRate: 60, background: "#100F0F", seed: 12
        });
        compare(args[args.length - 1], "decrypt");
        compare(args[args.indexOf("--canvas-width") + 1], "96");
        compare(args[args.indexOf("--canvas-height") + 1], "30");
        compare(args[args.indexOf("--frame-rate") + 1], "60");
        compare(args[args.indexOf("--terminal-background-color") + 1], "#100F0F");
        compare(args[args.indexOf("-i") + 1], "/banner.txt");
        // A pipe has no terminal to measure: without this ttfx ignores the
        // canvas flags above and falls back to 80x24.
        verify(args.indexOf("--ignore-terminal-dimensions") >= 0);
        // omarchy passes no gradient overrides, and neither does this: every
        // effect's own upstream colors are the point.
        verify(args.indexOf("--final-gradient-stops") < 0);
    }

    function test_args_clamp_the_seed_into_ttfxs_range() {
        var args = Ttfx.args({
            bannerPath: "/b", columns: 8, rows: 4, effect: "rain",
            frameRate: 0, background: "#000000", seed: 1786395783000
        });
        var seed = parseInt(args[args.indexOf("--seed") + 1], 10);
        verify(seed >= 0);
        verify(seed < 2147483647);
    }

    function test_args_drop_the_alpha_qml_puts_on_a_translucent_color() {
        var args = Ttfx.args({
            bannerPath: "/b", columns: 8, rows: 4, effect: "rain",
            frameRate: 60, background: "#80ff0000", seed: 1
        });
        // ttfx exits 2 on #aarrggbb, which would mean no screensaver at all.
        compare(args[args.indexOf("--terminal-background-color") + 1], "#ff0000");
        compare(Ttfx.normalizeColor("#100f0f"), "#100f0f");
        compare(Ttfx.normalizeColor("transparent"), "#000000");
    }

    function test_command_guards_against_ttfx_leaving_path() {
        var cmd = Ttfx.command({
            bannerPath: "/b", columns: 8, rows: 4, effect: "rain",
            frameRate: 60, background: "#000000", seed: 1
        });
        compare(cmd[0], "sh");
        compare(cmd[1], "-c");
        verify(cmd[2].indexOf("command -v ttfx") >= 0);
        verify(cmd[2].indexOf("exit 127") >= 0);
        compare(cmd[cmd.length - 1], "rain");
    }

    // wire protocol

    function test_frame_delimiter_is_restore_save_cursor_up_rows() {
        compare(Ttfx.frameDelimiter(30), esc + "8" + esc + "7" + esc + "[30A");
    }

    // frame parsing

    function test_parse_frame_splits_rows_and_keeps_columns() {
        var frame = "  AB  \n      \n  CD  ";
        var rows = Ttfx.parseFrame(frame);
        compare(rows.length, 3);
        compare(Ttfx.rowsToText(rows), ["  AB  ", "      ", "  CD  "]);
    }

    function test_parse_frame_reads_truecolor_runs() {
        var frame = "  " + esc + "[38;2;0;209;255mAB" + esc + "[0m  ";
        var runs = Ttfx.parseFrame(frame)[0];
        compare(runs.length, 3);
        compare(runs[0].text, "  ");
        compare(runs[0].color, "");
        compare(runs[1].col, 2);
        compare(runs[1].text, "AB");
        compare(runs[1].color, "#00d1ff");
        compare(runs[2].col, 4);
        compare(runs[2].color, "");
    }

    function test_parse_frame_pads_single_digit_color_channels() {
        var runs = Ttfx.parseFrame(esc + "[38;2;5;16;0mX")[0];
        compare(runs[0].color, "#051000");
    }

    function test_parse_frame_ignores_cursor_and_unmodelled_sequences() {
        // The tail ttfx writes on its very last frame, and the ESC7/ESC8 pair
        // it brackets a frame with: neither is a color change, and neither
        // occupies a column.
        var frame = esc + "7" + "AB" + esc + "[?25h";
        var runs = Ttfx.parseFrame(frame)[0];
        compare(runs.length, 1);
        compare(runs[0].col, 0);
        compare(runs[0].text, "AB");
    }

    function test_parse_frame_of_a_real_expand_frame() {
        // Frame 4 of the run in this file's header comment, verbatim.
        var frame = "            \n     "
            + esc + "[38;2;193;125;193mA" + esc + "[0m"
            + esc + "[38;2;204;150;204mB" + esc + "[0m     \n     "
            + esc + "[38;2;0;209;255mC" + esc + "[0m"
            + esc + "[38;2;0;209;255mD" + esc + "[0m     \n            ";
        var rows = Ttfx.parseFrame(frame);
        compare(rows.length, 4);
        compare(Ttfx.rowsToText(rows), [
            "            ",
            "     AB     ",
            "     CD     ",
            "            "
        ]);
        compare(rows[1][1].color, "#c17dc1");
        compare(rows[2][1].color, "#00d1ff");
    }
}

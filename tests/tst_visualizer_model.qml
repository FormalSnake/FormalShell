import QtQuick
import QtTest
import "../shell/Visualizer/model.js" as Model

TestCase {
    name: "VisualizerModel"

    function test_glyph_count_matches_eighth_block_levels() {
        compare(Model.GLYPHS.length, 8);
        compare(Model.GLYPHS[0], "▁");
        compare(Model.GLYPHS[7], "█");
    }

    function test_baseline_is_bar_count_copies_of_lowest_glyph() {
        var b = Model.baselineText();
        compare(b.length, Model.BAR_COUNT);
        for (var i = 0; i < b.length; i++)
            compare(b[i], Model.GLYPHS[0]);
    }

    function test_parse_frame_splits_on_semicolon() {
        var levels = Model.parseFrame("10;20;30", 3);
        compare(levels, [10, 20, 30]);
    }

    function test_parse_frame_pads_short_lines_with_zero() {
        var levels = Model.parseFrame("10;20", 5);
        compare(levels, [10, 20, 0, 0, 0]);
    }

    function test_parse_frame_ignores_extra_tokens() {
        var levels = Model.parseFrame("1;2;3;4;5", 3);
        compare(levels, [1, 2, 3]);
    }

    function test_parse_frame_treats_non_numeric_tokens_as_zero() {
        var levels = Model.parseFrame("12;abc;7", 3);
        compare(levels, [12, 0, 7]);
    }

    function test_parse_frame_treats_negative_values_as_zero() {
        var levels = Model.parseFrame("-5;3", 2);
        compare(levels, [0, 3]);
    }

    function test_parse_frame_handles_empty_line() {
        var levels = Model.parseFrame("", 4);
        compare(levels, [0, 0, 0, 0]);
    }

    function test_parse_frame_handles_undefined_line() {
        var levels = Model.parseFrame(undefined, 4);
        compare(levels, [0, 0, 0, 0]);
    }

    function test_parse_frame_handles_garbage_line() {
        var levels = Model.parseFrame("not cava output at all", 2);
        compare(levels, [0, 0]);
    }

    function test_level_to_glyph_zero_is_lowest() {
        compare(Model.levelToGlyph(0, 100), Model.GLYPHS[0]);
    }

    function test_level_to_glyph_max_is_highest() {
        compare(Model.levelToGlyph(100, 100), Model.GLYPHS[7]);
    }

    function test_level_to_glyph_midpoint_lands_midscale() {
        compare(Model.levelToGlyph(50, 100), Model.GLYPHS[4]);
    }

    function test_level_to_glyph_clamps_values_above_max() {
        // autosens can legitimately overshoot ascii_max_range momentarily.
        compare(Model.levelToGlyph(1000, 100), Model.GLYPHS[7]);
    }

    function test_level_to_glyph_clamps_negative_values() {
        compare(Model.levelToGlyph(-10, 100), Model.GLYPHS[0]);
    }

    function test_level_to_glyph_handles_zero_max_without_dividing_by_zero() {
        compare(Model.levelToGlyph(5, 0), Model.GLYPHS[0]);
    }

    function test_frame_to_text_renders_bar_count_glyphs() {
        var text = Model.frameToText("0;12;25;37;50;62;75;87;99;100", 10, 100);
        compare(text.length, 10);
        compare(text[0], Model.GLYPHS[0]);
        compare(text[9], Model.GLYPHS[7]);
    }

    function test_frame_to_text_of_empty_line_equals_baseline() {
        compare(Model.frameToText("", Model.BAR_COUNT, Model.MAX_LEVEL), Model.baselineText());
    }

    function test_frame_to_text_tolerates_malformed_line() {
        var text = Model.frameToText("garbage;;;not-numbers", Model.BAR_COUNT, Model.MAX_LEVEL);
        compare(text, Model.baselineText());
    }
}

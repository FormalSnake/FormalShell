import QtQuick
import QtTest
import "../shell/Visualizer/model.js" as Model

TestCase {
    name: "VisualizerModel"

    function test_baseline_is_bar_count_zeros() {
        var b = Model.baselineLevels();
        compare(b.length, Model.BAR_COUNT);
        for (var i = 0; i < b.length; i++)
            compare(b[i], 0);
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

    function test_level_to_fraction_zero_is_empty() {
        compare(Model.levelToFraction(0, 100), 0);
    }

    function test_level_to_fraction_max_is_full() {
        compare(Model.levelToFraction(100, 100), 1);
    }

    // sqrt, not linear: a quarter of the range reads half-scale. Linear
    // would put this at 0.25 and leave the fill pinned near empty for
    // everything a real track actually does.
    function test_level_to_fraction_applies_the_square_root_response_curve() {
        compare(Model.levelToFraction(25, 100), 0.5);
        verify(Math.abs(Model.levelToFraction(50, 100) - Math.sqrt(0.5)) < 1e-9);
    }

    // Doing what cava's deprecated `ignore` knob used to: near-silence is
    // flat (zero fill), not a jittering bottom pixel.
    function test_level_to_fraction_snaps_below_noise_floor_to_empty() {
        compare(Model.levelToFraction(Model.NOISE_FLOOR - 1, 100), 0);
        verify(Model.levelToFraction(Model.NOISE_FLOOR, 100) !== 0);
    }

    function test_level_to_fraction_clamps_values_above_max() {
        // cava can still overshoot ascii_max_range on a transient even with
        // autosens off.
        compare(Model.levelToFraction(1000, 100), 1);
    }

    function test_level_to_fraction_clamps_negative_values() {
        compare(Model.levelToFraction(-10, 100), 0);
    }

    function test_level_to_fraction_handles_zero_max_without_dividing_by_zero() {
        compare(Model.levelToFraction(5, 0), 0);
    }

    function test_frame_to_levels_renders_bar_count_fractions() {
        var levels = Model.frameToLevels("0;12;25;37;50;62;75;87;99;100", 10, 100);
        compare(levels.length, 10);
        compare(levels[0], 0);
        compare(levels[9], 1);
    }

    function test_frame_to_levels_of_empty_line_equals_baseline() {
        compare(Model.frameToLevels("", Model.BAR_COUNT, Model.MAX_LEVEL), Model.baselineLevels());
    }

    function test_frame_to_levels_tolerates_malformed_line() {
        var levels = Model.frameToLevels("garbage;;;not-numbers", Model.BAR_COUNT, Model.MAX_LEVEL);
        compare(levels, Model.baselineLevels());
    }

    function test_level_color_band_zero_is_dim() {
        compare(Model.levelColorBand(0), "dim");
    }

    function test_level_color_band_just_below_dim_threshold_is_dim() {
        compare(Model.levelColorBand(Model.LEVEL_DIM_BELOW - 0.01), "dim");
    }

    function test_level_color_band_at_dim_threshold_is_content() {
        compare(Model.levelColorBand(Model.LEVEL_DIM_BELOW), "content");
    }

    function test_level_color_band_mid_range_is_content() {
        compare(Model.levelColorBand(0.6), "content");
    }

    function test_level_color_band_just_below_accent_threshold_is_content() {
        compare(Model.levelColorBand(Model.LEVEL_ACCENT_FROM - 0.01), "content");
    }

    function test_level_color_band_at_accent_threshold_is_accent() {
        compare(Model.levelColorBand(Model.LEVEL_ACCENT_FROM), "accent");
    }

    function test_level_color_band_full_scale_is_accent() {
        compare(Model.levelColorBand(1), "accent");
    }

    function test_baseline_is_bar_count_long() {
        compare(Model.baselineLevels().length, 24);
        compare(Model.BAR_COUNT, 24);
    }

    function test_downsample_takes_the_peak_of_each_group() {
        var levels = [1, 2, 3, 4, 9, 1, 2, 3, 5, 6, 7, 8, 1, 1, 1, 1, 9, 1, 1, 1, 1, 1, 1, 5];
        var d = Model.downsample(levels, 6);
        compare(d, [4, 9, 8, 1, 9, 5]);
    }

    function test_downsample_short_input_pads_with_zeros() {
        var d = Model.downsample([3, 7], 6);
        compare(d, [3, 7, 0, 0, 0, 0]);
    }

    function test_downsample_empty_input_is_all_zeros() {
        compare(Model.downsample([], 6), [0, 0, 0, 0, 0, 0]);
    }

    function test_downsample_count_equal_to_length_is_identity() {
        var levels = [1, 2, 3, 4, 5, 6];
        compare(Model.downsample(levels, 6), levels);
    }
}

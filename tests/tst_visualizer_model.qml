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

    // Linear: the curve lives in normalize, after the gain stage.
    function test_level_to_fraction_is_linear() {
        compare(Model.levelToFraction(250, 1000), 0.25);
    }

    // Doing what cava's deprecated `ignore` knob used to: near-silence is
    // flat (zero fill), not a jittering bottom pixel.
    function test_level_to_fraction_snaps_below_noise_floor_to_empty() {
        compare(Model.levelToFraction(Model.NOISE_FLOOR - 1, Model.MAX_LEVEL), 0);
        verify(Model.levelToFraction(Model.NOISE_FLOOR, Model.MAX_LEVEL) !== 0);
    }

    function test_level_to_fraction_clamps_values_above_max() {
        // cava can still overshoot ascii_max_range on a transient even with
        // autosens off.
        compare(Model.levelToFraction(5000, 1000), 1);
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

    // cava writes the left channel high to low, then the right low to high,
    // with a trailing delimiter before the newline.
    function test_stereo_frame_splits_the_mirrored_halves_into_channels() {
        var s = Model.stereoFrameToLevels("40;30;20;10;60;70;80;100;", 4, 100);
        compare(s.left, [0.1, 0.2, 0.3, 0.4]);
        compare(s.right, [0.6, 0.7, 0.8, 1]);
        compare(s.mono, [0.35, 0.45, 0.55, 0.7]);
    }

    function test_stereo_frame_mono_is_the_average_before_the_noise_floor() {
        var n = Model.NOISE_FLOOR;
        var s = Model.stereoFrameToLevels([n - 3, 0, 0, n + 1].join(";"), 2, Model.MAX_LEVEL);
        compare(s.left, [0, 0]);
        compare(s.right, [0, (n + 1) / Model.MAX_LEVEL]);
        compare(s.mono, [0, 0]);
    }

    function test_stereo_frame_of_a_centred_source_matches_its_mono_frame() {
        var mono = "10;200;500;900";
        var s = Model.stereoFrameToLevels("900;500;200;10;10;200;500;900", 4, Model.MAX_LEVEL);
        compare(s.mono, Model.frameToLevels(mono, 4, Model.MAX_LEVEL));
        compare(s.left, s.mono);
        compare(s.right, s.mono);
    }

    function test_stereo_frame_tolerates_short_and_malformed_lines() {
        var s = Model.stereoFrameToLevels("garbage;;", Model.BAR_COUNT, Model.MAX_LEVEL);
        compare(s.mono, Model.baselineLevels());
        compare(s.left, Model.baselineLevels());
        compare(s.right, Model.baselineLevels());
        var u = Model.stereoFrameToLevels(undefined, 3, 100);
        compare(u.left.length, 3);
        compare(u.right, [0, 0, 0]);
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

    function test_smooth_levels_moves_toward_the_target() {
        var result = Model.smoothLevels([0], [1], Model.RISE_SECONDS);
        verify(result[0] > 0);
        verify(result[0] < 1);
    }

    function test_smooth_levels_rises_faster_than_it_falls() {
        var dt = 0.02;
        var rising = Model.smoothLevels([0], [1], dt);
        var falling = Model.smoothLevels([1], [0], dt);
        var riseDelta = rising[0] - 0;
        var fallDelta = 1 - falling[0];
        verify(riseDelta > fallDelta);
    }

    function test_smooth_levels_zero_dt_does_not_move() {
        compare(Model.smoothLevels([0.5], [1], 0), [0.5]);
    }

    function test_smooth_levels_non_finite_dt_does_not_move() {
        compare(Model.smoothLevels([0.5], [1], NaN), [0.5]);
        compare(Model.smoothLevels([0.5], [1], -1), [0.5]);
        compare(Model.smoothLevels([0.5], [1], undefined), [0.5]);
    }

    function test_smooth_levels_converges_within_half_a_second_of_16ms_steps() {
        var shown = [0];
        var target = [1];
        var steps = Math.round(0.5 / 0.016);
        for (var i = 0; i < steps; i++)
            shown = Model.smoothLevels(shown, target, 0.016);
        verify(Math.abs(shown[0] - 1) < 0.01);
    }

    function test_smooth_levels_reconciles_lengths_to_the_target() {
        compare(Model.smoothLevels([1, 2, 3], [0, 0], 0.03).length, 2);
        compare(Model.smoothLevels([1], [0, 0, 0], 0.03).length, 3);
        // A missing shown value starts from 0, not undefined.
        var grown = Model.smoothLevels([1], [1, 1], Model.RISE_SECONDS);
        verify(grown[1] > 0);
    }

    function test_smooth_levels_empty_target_is_empty() {
        compare(Model.smoothLevels([1, 2, 3], [], 0.03), []);
    }

    // Two windows syncing at different refresh rates (240Hz, 144Hz) feed
    // this different, irregular dt every call; the factor has to be a
    // function of dt alone, not of an assumed frame length, or the two
    // screens would carry the same levels at visibly different speeds.
    function test_smooth_levels_is_time_invariant_not_frame_count_invariant() {
        var twoSteps = Model.smoothLevels(Model.smoothLevels([0], [1], 0.008), [1], 0.008);
        var oneStep = Model.smoothLevels([0], [1], 0.016);
        verify(Math.abs(twoSteps[0] - oneStep[0]) < 1e-6);
    }

    function test_smooth_levels_large_dt_moves_nearly_all_the_way() {
        // dt this far past RISE_SECONDS (0.1s against a 0.03s time
        // constant) should land past 95% of the way there.
        var result = Model.smoothLevels([0], [1], 0.1);
        verify(result[0] > 0.95);
    }

    // Runs `seconds` of identical frames at cava's own 120fps through the
    // gain stage and returns the running peak it settles on.
    function _run(ref, frame, seconds) {
        var dt = 1 / 120;
        var steps = Math.round(seconds / dt);
        for (var i = 0; i < steps; i++)
            ref = Model.agcStep(ref, Model.framePeak(frame), dt);
        return ref;
    }

    function _scaled(shape, gain) {
        return shape.map(function (v) { return v * gain; });
    }

    // The complaint: a louder track or a raised volume pegged every column.
    // The same passage at three input gains settles on the same drawn
    // height, and under 0.9.
    function test_agc_levels_one_passage_at_any_gain_to_the_same_height() {
        var shape = [0.2, 0.5, 1, 0.7, 0.3];
        var heights = [];
        var gains = [0.1, 0.3, 0.9];
        for (var g = 0; g < gains.length; g++) {
            var frame = _scaled(shape, gains[g]);
            var ref = _run(0, frame, 2);
            heights.push(Model.framePeak(Model.levelFrame(frame, ref)));
        }
        for (var i = 0; i < heights.length; i++) {
            verify(heights[i] < 0.9, "gain " + gains[i] + " drew " + heights[i]);
            verify(heights[i] > 0.67, "gain " + gains[i] + " drew " + heights[i]);
            verify(Math.abs(heights[i] - heights[0]) < 1e-6);
        }
        verify(heights[0] < Model.LEVEL_ACCENT_FROM);
    }

    function test_agc_quiet_passage_after_a_loud_one_recovers_within_the_release_time() {
        var loud = [0.8, 0.4];
        var quiet = [0.08, 0.04];
        var ref = _run(0, loud, 2);
        var steady = Model.framePeak(Model.levelFrame(loud, ref));
        var halfway = _run(ref, quiet, Model.AGC_RELEASE_SECONDS / 2);
        verify(Model.framePeak(Model.levelFrame(quiet, halfway)) < steady - 0.1);
        ref = _run(ref, quiet, Model.AGC_RELEASE_SECONDS + 0.1);
        verify(Math.abs(Model.framePeak(Model.levelFrame(quiet, ref)) - steady) < 0.01);
    }

    function test_agc_silence_under_the_noise_floor_stays_flat() {
        var frame = Model.frameToLevels([1, 2, 3, 4].map(function () { return Model.NOISE_FLOOR - 1; }).join(";"), 4, Model.MAX_LEVEL);
        var ref = _run(0, frame, 5);
        compare(ref, Model.AGC_FLOOR);
        compare(Model.levelFrame(frame, ref), [0, 0, 0, 0]);
    }

    function test_agc_floor_keeps_a_band_just_over_the_noise_floor_low() {
        var frame = [Model.NOISE_FLOOR / Model.MAX_LEVEL];
        var ref = _run(0, frame, 5);
        verify(Model.levelFrame(frame, ref)[0] < 0.2);
    }

    function test_agc_transient_over_the_running_peak_draws_taller_than_the_steady_level() {
        var steadyFrame = [0.3, 0.15];
        var ref = _run(0, steadyFrame, 2);
        var steady = Model.levelFrame(steadyFrame, ref)[0];
        var hitFrame = [0.9, 0.15];
        ref = Model.agcStep(ref, Model.framePeak(hitFrame), 1 / 120);
        var hit = Model.levelFrame(hitFrame, ref)[0];
        verify(hit > steady);
        verify(hit >= Model.LEVEL_ACCENT_FROM);
        verify(hit < 1);
        verify(steady < Model.LEVEL_ACCENT_FROM);
    }

    function test_agc_preserves_band_order_and_contrast() {
        var frame = [0.05, 0.1, 0.2, 0.4];
        var ref = _run(0, frame, 2);
        var drawn = Model.levelFrame(frame, ref);
        for (var i = 1; i < drawn.length; i++)
            verify(drawn[i] - drawn[i - 1] > 0.1, "band " + i + ": " + drawn);
        // A band a quarter of the peak reads dim, the peak does not.
        compare(Model.levelColorBand(drawn[1]), "dim");
        compare(Model.levelColorBand(drawn[3]), "content");
    }

    function test_agc_step_from_reset_snaps_to_the_first_peak() {
        compare(Model.agcStep(0, 0.5, 1 / 120), 0.5);
        compare(Model.agcStep(0, 0, 1 / 120), Model.AGC_FLOOR);
    }

    function test_agc_step_does_not_move_on_a_bad_dt() {
        compare(Model.agcStep(0.5, 0.9, 0), 0.5);
        compare(Model.agcStep(0.5, 0.1, NaN), 0.5);
    }

    function test_normalize_approaches_one_and_never_reaches_it() {
        var h = Model.normalize(1, 0.1);
        verify(h > 0.99);
        verify(h < 1);
        compare(Model.normalize(0, 0.1), 0);
    }
}

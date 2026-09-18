import QtQuick
import QtTest
import "../shell/Theme/barpaint.js" as Paint

// M60 T3: wingpanel's adaptive band. The statistics are read off a Canvas
// (Theme/BarPaint.qml) and the decision they feed is pure, so every branch
// of it is exercised here against synthetic stats rather than against a
// wallpaper: three thresholds, the sigma rule at its own boundary, the mode
// picking between the two translucent paints, and a window covering the
// output winning over all of it.
TestCase {
    name: "BarPaint"

    function stats(mean, std, acutance) {
        return { mean: mean, std: std, acutance: acutance, sampled: true };
    }

    // --- The statistics --------------------------------------------------

    // One RGBA run of a grey ramp, laid out row by row the way
    // getImageData().data hands it over.
    function pixels(values) {
        var out = [];
        for (var i = 0; i < values.length; i++)
            out.push(values[i], values[i], values[i], 255);
        return out;
    }

    function test_a_flat_field_has_its_own_mean_and_no_spread_or_edges() {
        var s = Paint.stats(pixels([200, 200, 200, 200]), 4, 1);
        verify(s.sampled);
        fuzzyCompare(s.mean, 200, 0.001);
        fuzzyCompare(s.std, 0, 0.001);
        fuzzyCompare(s.acutance, 0, 0.001);
    }

    // Black and white alternating: the mean sits in the middle, the spread
    // is the half-distance, and every adjacent pair is a full-range edge.
    function test_a_checker_row_carries_the_spread_and_the_edges() {
        var s = Paint.stats(pixels([0, 255, 0, 255]), 4, 1);
        fuzzyCompare(s.mean, 127.5, 0.001);
        fuzzyCompare(s.std, 127.5, 0.001);
        fuzzyCompare(s.acutance, 255, 0.001);
    }

    // The acutance is horizontal, so rows that differ from each other but
    // are flat in themselves carry no edge at all.
    function test_acutance_reads_along_a_row_and_not_down_a_column() {
        var s = Paint.stats(pixels([0, 0, 255, 255]), 2, 2);
        fuzzyCompare(s.mean, 127.5, 0.001);
        fuzzyCompare(s.acutance, 0, 0.001);
    }

    function test_no_samples_is_not_a_reading() {
        var s = Paint.stats([], 0, 0);
        verify(!s.sampled);
    }

    // --- The decision ----------------------------------------------------

    function test_a_calm_bright_band_takes_dark_ink_on_no_fill() {
        compare(Paint.decide(stats(230, 0, 0), "dark", false), "dark");
    }

    function test_a_calm_dark_band_takes_light_ink_on_no_fill() {
        compare(Paint.decide(stats(30, 0, 0), "dark", false), "light");
    }

    // Each of the three busy terms on its own, against a mean that is calm
    // enough on its own not to decide anything.
    function test_spread_alone_makes_a_band_busy() {
        verify(!Paint.busy(stats(60, Paint.STD_THRESHOLD, 0)));
        verify(Paint.busy(stats(60, Paint.STD_THRESHOLD + 1, 0)));
    }

    function test_acutance_alone_makes_a_band_busy() {
        verify(!Paint.busy(stats(60, 0, Paint.ACUTANCE_THRESHOLD)));
        verify(Paint.busy(stats(60, 0, Paint.ACUTANCE_THRESHOLD + 1)));
    }

    // The sigma rule: a band whose mean is under the threshold but whose
    // spread puts its brightest twentieth over it. At std 40 the term is
    // 180 - 1.645 * 40 = 114.2, so a mean either side of that decides it
    // while neither the spread nor the acutance does.
    function test_the_sigma_rule_catches_a_dark_band_with_bright_parts() {
        var boundary = Paint.LUMA_THRESHOLD - Paint.SIGMA * 40;
        verify(!Paint.busy(stats(boundary - 1, 40, 0)));
        verify(Paint.busy(stats(boundary + 1, 40, 0)));
    }

    // A mean over the threshold takes the bright branch before the sigma
    // rule is consulted at all, so a bright band with the same spread is
    // calm.
    function test_a_bright_band_is_not_busy_by_the_sigma_rule() {
        verify(!Paint.busy(stats(200, 40, 0)));
        compare(Paint.decide(stats(200, 40, 0), "dark", false), "dark");
    }

    function test_the_mode_picks_between_the_two_translucent_paints() {
        var busy = stats(120, 80, 0);
        compare(Paint.decide(busy, "dark", false), "translucentDark");
        compare(Paint.decide(busy, "light", false), "translucentLight");
    }

    function test_a_window_covering_the_output_wins_over_every_reading() {
        compare(Paint.decide(stats(230, 0, 0), "dark", true), "maximized");
        compare(Paint.decide(stats(120, 80, 0), "light", true), "maximized");
        compare(Paint.decide(null, "dark", true), "maximized");
    }

    // No wallpaper set is not a dark wallpaper: nothing is sampled and the
    // band says so rather than inventing a reading.
    function test_nothing_sampled_reads_as_the_bare_band() {
        compare(Paint.decide(null, "dark", false), "light");
        compare(Paint.decide({ mean: 0, std: 0, acutance: 0, sampled: false }, "light", false), "light");
    }

    // --- The pin ---------------------------------------------------------

    // `bar.paint` (M62). The rule is the default and the answer to anything
    // that is not one of the seven, the same unknown-value habit
    // presets.js keeps for `theme.preset`.
    function test_an_unknown_pin_reads_as_the_rule() {
        compare(Paint.pin("auto"), "auto");
        compare(Paint.pin("transparent"), "transparent");
        compare(Paint.pin("translucentDark"), "translucentDark");
        compare(Paint.pin("solid"), "auto");
        compare(Paint.pin(""), "auto");
        compare(Paint.pin(42), "auto");
        compare(Paint.pin(null), "auto");
        compare(Paint.pin(undefined), "auto");
        // An inherited Object property is not a pin either.
        compare(Paint.pin("constructor"), "auto");
    }

    // A pinned paint is the answer whatever is under the band, a window
    // covering the output included: pinning is the user saying they have
    // looked.
    function test_a_pinned_paint_wins_over_the_sample() {
        var busy = stats(120, 80, 0);
        compare(Paint.decide(busy, "dark", false, "light"), "light");
        compare(Paint.decide(stats(230, 0, 0), "dark", false, "translucentDark"), "translucentDark");
        compare(Paint.decide(busy, "dark", true, "dark"), "dark");
        compare(Paint.decide(null, "dark", false, "maximized"), "maximized");
    }

    // `auto` is what every session had before the key existed, so the four
    // readings above are unchanged by it and by its absence alike.
    function test_auto_samples_the_way_it_always_did() {
        var busy = stats(120, 80, 0);
        compare(Paint.decide(busy, "dark", false, "auto"), Paint.decide(busy, "dark", false));
        compare(Paint.decide(busy, "light", false, "auto"), "translucentLight");
        compare(Paint.decide(stats(230, 0, 0), "dark", false, "auto"), "dark");
        compare(Paint.decide(stats(30, 0, 0), "dark", false, "auto"), "light");
        compare(Paint.decide(stats(30, 0, 0), "dark", true, "auto"), "maximized");
        // An unknown value falls back to the rule rather than to a paint.
        compare(Paint.decide(busy, "dark", false, "solid"), "translucentDark");
    }

    // `transparent` is the rule with the busy branch taken out: no fill on a
    // band the wallpaper would have filled, and the ink still follows the
    // wallpaper's own mean rather than being pinned with it.
    function test_transparent_drops_the_fill_and_keeps_the_ink_adaptive() {
        compare(Paint.decide(stats(120, 80, 0), "dark", false, "transparent"), "light");
        compare(Paint.decide(stats(230, 80, 0), "dark", false, "transparent"), "dark");
        compare(Paint.decide(stats(200, 80, 20), "light", false, "transparent"), "dark");
        compare(Paint.decide(stats(30, 0, 0), "dark", false, "transparent"), "light");
        // Nothing sampled is still the bare band with light ink.
        compare(Paint.decide(null, "dark", false, "transparent"), "light");
        // A window over the output still takes it solid: none of the
        // wallpaper is visible to be transparent over.
        compare(Paint.decide(stats(230, 0, 0), "dark", true, "transparent"), "maximized");
    }

    // --- The band's rect -------------------------------------------------

    // The bar's own edge and thickness against the output, scaled into the
    // sample: a 40px band on a 1080-tall output is 5 rows of a 135-row
    // sample, at the top for a top bar and at the far side for the other
    // three.
    function test_the_band_rect_follows_the_bar_edge() {
        var top = Paint.bandRect("top", 40, 1920, 1080, 240, 135);
        compare(top.x, 0);
        compare(top.y, 0);
        compare(top.width, 240);
        compare(top.height, 5);

        var bottom = Paint.bandRect("bottom", 40, 1920, 1080, 240, 135);
        compare(bottom.y, 130);
        compare(bottom.height, 5);

        var right = Paint.bandRect("right", 40, 1920, 1080, 240, 135);
        compare(right.width, 5);
        compare(right.height, 135);
        compare(right.x, 235);

        var left = Paint.bandRect("left", 40, 1920, 1080, 240, 135);
        compare(left.x, 0);
        compare(left.width, 5);
    }

    // A band thinner than one sample row still has a row to read.
    function test_the_band_rect_never_collapses() {
        var band = Paint.bandRect("top", 1, 1920, 1080, 240, 135);
        compare(band.height, 1);
    }
}

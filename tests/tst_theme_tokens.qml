import QtQuick
import QtTest
import "../shell/Theme/tokens.js" as Tokens

TestCase {
    name: "ThemeTokens"

    // 1.3 scale roots

    function test_font_scale_is_base_over_thirteen() {
        compare(Tokens.fontScale(13), 1.0);
        compare(Tokens.fontScale(26), 2.0);
    }

    function test_font_tokens_at_default_base_match_design_doc_table() {
        var f = Tokens.fontTokens(13);
        compare(f.caption, 11);
        compare(f.bodySmall, 12);
        compare(f.body, 13);
        compare(f.subtitle, 14);
        compare(f.title, 15);
        compare(f.heading, 17);
        compare(f.display, 26);
        compare(f.displayLarge, 30);
    }

    function test_font_tokens_rescale_proportionally_with_base_size() {
        var f = Tokens.fontTokens(16);
        compare(f.baseSize, 16);
        compare(f.body, 16);
        compare(f.caption, Math.round(16 * 0.833));
        compare(f.display, Math.round(16 * 2.0));
    }

    function test_spacing_tokens_at_scale_one_match_design_doc_table() {
        var s = Tokens.spacingTokens(1.0);
        compare(s.xxs, 2);
        compare(s.xs, 3);
        compare(s.sm, 4);
        compare(s.md, 6);
        compare(s.lg, 8);
        compare(s.xl, 10);
        compare(s.xxl, 12);
        compare(s.huge, 18);
        compare(s.controlGap, 8);
        compare(s.popupRowHeight, 28);
        compare(s.trackThickness, 6);
    }

    // shadcn redesign (2026-08-25): controlHeight/barCellHeight/barMargin/
    // controlPaddingX/Y/rowGap/iconGap/panelPadding/sectionGap and the
    // popup widths take the spec's own values, decoupled from the bare
    // scale steps they used to mirror.
    function test_semantic_spacing_tokens_match_the_shadcn_table() {
        var s = Tokens.spacingTokens(1.0);
        compare(s.controlHeight, 32);
        compare(s.barCellHeight, 28);
        compare(s.barMargin, 6);
        compare(s.controlPaddingX, 12);
        compare(s.controlPaddingY, 6);
        compare(s.rowGap, 4);
        compare(s.iconGap, 8);
        compare(s.panelPadding, 12);
        compare(s.sectionGap, 16);
        compare(s.screenPadding, 12);
        compare(s.popupWidthNarrow, 320);
        compare(s.popupWidthDefault, 380);
        compare(s.popupWidthWide, 480);
        compare(s.popupWidthMenu, 560);
        compare(s.popupWidthMenuSplit, 840);
        compare(s.popupWidthMenuApp, 900);
    }

    function test_spacing_tokens_rescale_with_scale_factor() {
        var s = Tokens.spacingTokens(2.0);
        compare(s.sm, 8);
        compare(s.panelPadding, 24);
        compare(s.trackThickness, 12);
        compare(s.controlHeight, 64);
        compare(s.barMargin, 12);
    }

    // 1.3 radius tokens (shadcn redesign, spec "Radius")

    function test_radius_tokens_at_default_base_match_the_spec_table() {
        var r = Tokens.radiusTokens(10);
        compare(r.sm, 6);
        compare(r.md, 8);
        compare(r.lg, 10);
        compare(r.xl, 14);
    }

    function test_radius_tokens_track_a_custom_base() {
        var r = Tokens.radiusTokens(20);
        compare(r.sm, 16);
        compare(r.md, 18);
        compare(r.lg, 20);
        compare(r.xl, 24);
    }

    function test_radius_tokens_floor_at_two() {
        var r = Tokens.radiusTokens(0);
        compare(r.sm, 2);
        compare(r.md, 2);
        compare(r.lg, 2);
        compare(r.xl, 4);
    }

    // Weight tokens (shadcn redesign, spec "Type")

    function test_weights_match_the_shadcn_table() {
        compare(Tokens.WEIGHTS.normal, 400);
        compare(Tokens.WEIGHTS.medium, 500);
        compare(Tokens.WEIGHTS.semibold, 600);
    }

    // clamp (shadcn redesign, spec "Depth"): what holds
    // `theme.surfaceOpacity` inside 0..1.

    function test_clamp_passes_a_value_already_in_range() {
        compare(Tokens.clamp(0.85, 0, 1, 0.85), 0.85);
        compare(Tokens.clamp(0, 0, 1, 0.85), 0);
        compare(Tokens.clamp(1, 0, 1, 0.85), 1);
    }

    function test_clamp_holds_a_value_at_the_bounds() {
        compare(Tokens.clamp(-3, 0, 1, 0.85), 0);
        compare(Tokens.clamp(42, 0, 1, 0.85), 1);
    }

    // A malformed alpha resolves to the caller's own default rather than to
    // `min`, which would paint every card invisible.
    function test_clamp_falls_back_on_anything_that_is_not_a_number() {
        compare(Tokens.clamp(undefined, 0, 1, 0.85), 0.85);
        compare(Tokens.clamp(null, 0, 1, 0.85), 0.85);
        compare(Tokens.clamp("opaque", 0, 1, 0.85), 0.85);
        compare(Tokens.clamp(NaN, 0, 1, 0.85), 0.85);
        compare(Tokens.clamp(Infinity, 0, 1, 0.85), 0.85);
    }

    // A JSON number arriving as a string still reads as the number it is.
    function test_clamp_accepts_a_numeric_string() {
        compare(Tokens.clamp("0.5", 0, 1, 0.85), 0.5);
    }

    // letter-spacing tokens

    function test_letter_spacing_tokens_at_scale_one() {
        var l = Tokens.letterSpacingTokens(1.0);
        compare(l.meta, 1);
        compare(l.wide, 2);
        compare(l.display, 6);
    }

    function test_letter_spacing_tokens_rescale_with_font_scale() {
        var l = Tokens.letterSpacingTokens(2.0);
        compare(l.meta, 2);
        compare(l.wide, 4);
        compare(l.display, 12);
    }

    // §4 motion tokens

    function test_motion_tokens_sit_inside_the_design_bands() {
        var m = Tokens.motionTokens(true);
        verify(m.fast >= 90 && m.fast <= 140);
        verify(m.standard >= 90 && m.standard <= 140);
        verify(m.fast <= m.standard);
        verify(m.slide >= 4 && m.slide <= 8);
    }

    function test_motion_tokens_disabled_zeroes_durations_not_distance() {
        var m = Tokens.motionTokens(false);
        compare(m.fast, 0);
        compare(m.standard, 0);
        compare(m.slide, Tokens.motionTokens(true).slide);
    }

    // M48: the workspace pill's travel spans a whole row of dots, which
    // `standard` reads as a jump, so it takes a step of its own outside the
    // 90-140ms control band while still being ordinary chrome.
    function test_motion_tokens_emphasized_is_the_indicator_step() {
        var m = Tokens.motionTokens(true);
        compare(m.emphasized, 250);
        verify(m.emphasized > m.standard);
    }

    function test_motion_tokens_disabled_zeroes_emphasized_too() {
        compare(Tokens.motionTokens(false).emphasized, 0);
    }

    function test_motion_tokens_reveal_is_the_400ms_carve_out() {
        var m = Tokens.motionTokens(true);
        compare(m.reveal, 400);
    }

    function test_motion_tokens_disabled_zeroes_reveal_too() {
        var m = Tokens.motionTokens(false);
        compare(m.reveal, 0);
    }

    // M16 Task 11: marquee carve-out — a rate and a hold, not a duration,
    // so `enabled: false` leaves it alone; the consumer gates the whole
    // animation on `Theme.motionEnabled` itself instead.
    function test_motion_tokens_marquee_pace_matches_the_owner_brief() {
        var m = Tokens.motionTokens(true);
        compare(m.marqueePxPerSec, 30);
        compare(m.marqueeHoldMs, 2000);
    }

    function test_motion_tokens_marquee_is_not_zeroed_when_disabled() {
        var enabled = Tokens.motionTokens(true);
        var disabled = Tokens.motionTokens(false);
        compare(disabled.marqueePxPerSec, enabled.marqueePxPerSec);
        compare(disabled.marqueeHoldMs, enabled.marqueeHoldMs);
    }

    // Regression guard (M16 Task 1): the legacy fixed Theme.spacing object
    // ({xs:2, sm:4, md:8, lg:16}, never scaling) is deleted from Theme.qml,
    // every consumer migrated onto the scaling `space` set above. The
    // Singleton itself isn't reachable from qmltestrunner (no `qs.*` module
    // resolution outside the real Quickshell engine — no test in this suite
    // imports one), so this reads Theme.qml's own source text via the same
    // XHR-file-read pattern tst_menu_emoji.qml uses, and asserts the
    // property declaration is gone rather than merely unused — so it can't
    // silently return.
    function test_legacy_theme_spacing_property_is_deleted() {
        var done = false;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) done = true;
        };
        xhr.open("GET", Qt.resolvedUrl("../shell/Core/Theme.qml"));
        xhr.send();
        tryVerify(function () { return done; }, 5000);
        verify(xhr.responseText.indexOf("property var spacing") === -1);
    }
}

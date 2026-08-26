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
        compare(s.barCellWidth, 44);
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

    // M49 D2: a base of 0 is the retro preset asking for square corners, so
    // it returns zeros outright and the 2px floor only applies to a
    // positive base.
    function test_radius_tokens_are_all_zero_at_a_zero_base() {
        var r = Tokens.radiusTokens(0);
        compare(r.sm, 0);
        compare(r.md, 0);
        compare(r.lg, 0);
        compare(r.xl, 0);
        compare(Tokens.radiusTokens("square").xl, 0);
    }

    // A cover's corner is a quarter of its own shorter side, capped at `sm`:
    // the ladder is sized for controls, and `sm` on the bar's 17px album art
    // reads as a lozenge rather than a rounded square.
    function test_cover_radius_is_a_quarter_of_the_slot() {
        var sm = Tokens.radiusTokens(10).sm;
        compare(sm, 6);
        compare(Tokens.coverRadius(sm, 17), 4);
        compare(Tokens.coverRadius(sm, 12), 3);
    }

    // Big enough and it lands back on the ladder rather than growing past it.
    function test_cover_radius_caps_at_the_small_step() {
        var sm = Tokens.radiusTokens(10).sm;
        compare(Tokens.coverRadius(sm, 96), sm);
        compare(Tokens.coverRadius(sm, 400), sm);
    }

    // Never rounds away to nothing on a slot small enough to floor it, and
    // never anywhere near a circle: a circle on a 17px slot is 8.5.
    function test_cover_radius_floors_at_two_and_never_reaches_a_circle() {
        var sm = Tokens.radiusTokens(10).sm;
        compare(Tokens.coverRadius(sm, 4), 2);
        compare(Tokens.coverRadius(sm, 0), 2);
        verify(Tokens.coverRadius(sm, 17) < 17 / 2);
        verify(Tokens.coverRadius(sm, 96) < 96 / 2);
    }

    // The retro preset squares every corner, and `sm` is already 0 there, so
    // covers square with everything else rather than needing their own check.
    function test_cover_radius_is_square_at_a_zero_base() {
        compare(Tokens.coverRadius(Tokens.radiusTokens(0).sm, 17), 0);
        compare(Tokens.coverRadius(0, 96), 0);
    }

    function test_radius_tokens_floor_at_two_on_a_positive_base() {
        var r = Tokens.radiusTokens(1);
        compare(r.sm, 2);
        compare(r.md, 2);
        compare(r.lg, 2);
        compare(r.xl, 5);
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
    // Interaction states

    // The wash is a lift on a dark theme and a knock-down on a light one,
    // which is what makes it read the same over any wallpaper: the ink is
    // always the far end from the surface it sits on.
    function test_state_alpha_has_a_step_per_mode() {
        var dark = Tokens.stateAlpha("dark");
        var light = Tokens.stateAlpha("light");
        verify(dark.press > dark.hover);
        verify(light.press > light.hover);
        // Dark ink is white over a near-black card, light ink is black over
        // white; white needs the larger alpha to move the same distance.
        verify(dark.hover > light.hover);
    }

    // The bar strip is `card`, not `background`, so the hover has that much
    // less room to read against than a shadcn ghost button does: zinc's own
    // accent-over-card is white at 0.07, and the wash steps past it.
    function test_state_alpha_hover_clears_zinc_accent_over_card() {
        verify(Tokens.stateAlpha("dark").hover > 0.07);
        verify(Tokens.stateAlpha("light").hover > 0.043);
    }

    // shadcn's `/90` on a control that already carries a colour, the same
    // either way round: a fill blends toward `background` rather than
    // washing toward the ink.
    function test_state_alpha_filled_steps_match_across_modes() {
        compare(Tokens.stateAlpha("dark").filledHover, Tokens.stateAlpha("light").filledHover);
        compare(Tokens.stateAlpha("dark").filledPress, Tokens.stateAlpha("light").filledPress);
        verify(Tokens.stateAlpha("dark").filledPress > Tokens.stateAlpha("dark").filledHover);
    }

    // Anything that is not the light theme is the dark one, the same default
    // Palette.fallback() takes for a theme.json with no `mode`.
    function test_state_alpha_defaults_to_dark() {
        compare(Tokens.stateAlpha(undefined).hover, Tokens.stateAlpha("dark").hover);
        compare(Tokens.stateAlpha("").hover, Tokens.stateAlpha("dark").hover);
    }

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

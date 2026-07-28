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
        compare(s.xxxl, 14);
        compare(s.huge, 18);
        compare(s.controlGap, 8);
        compare(s.controlPaddingX, 10);
        compare(s.controlPaddingY, 6);
        compare(s.inputPaddingY, 7);
        compare(s.controlHeight, 28);
        compare(s.popupRowHeight, 28);
        compare(s.rowGap, 8);
        compare(s.rowPaddingX, 12);
        compare(s.labelGap, 4);
        compare(s.panelGap, 14);
        compare(s.panelPadding, 18);
        compare(s.popupPadding, 14);
    }

    function test_spacing_tokens_rescale_with_scale_factor() {
        var s = Tokens.spacingTokens(2.0);
        compare(s.sm, 8);
        compare(s.panelPadding, 36);
    }

    // 1.1 four interactive states

    function test_state_appearance_normal() {
        var a = Tokens.stateAppearance("normal");
        compare(a.fillAlpha, 0.04);
        compare(a.borderWidth, 2);
        compare(a.borderAlpha, 0.4);
    }

    function test_state_appearance_hover_cursor() {
        var a = Tokens.stateAppearance("hover-cursor");
        compare(a.fillAlpha, 0.08);
        compare(a.borderWidth, 2);
        compare(a.borderAlpha, 0.25);
    }

    function test_state_appearance_selected_is_borderless() {
        var a = Tokens.stateAppearance("selected");
        compare(a.fillAlpha, 0.18);
        compare(a.borderWidth, 0);
        compare(a.borderAlpha, 1.0);
    }

    function test_state_appearance_focus_mirrors_hover_cursor() {
        compare(JSON.stringify(Tokens.stateAppearance("focus")), JSON.stringify(Tokens.stateAppearance("hover-cursor")));
    }

    function test_state_appearance_pressed() {
        var a = Tokens.stateAppearance("pressed");
        compare(a.fillAlpha, 0.22);
    }

    function test_state_appearance_unknown_name_falls_back_to_normal() {
        compare(JSON.stringify(Tokens.stateAppearance("bogus")), JSON.stringify(Tokens.stateAppearance("normal")));
    }

    function test_resolve_state_pressed_wins_over_everything() {
        compare(Tokens.resolveState({ pressed: true, focused: true, focusable: true, hovered: true, selected: true }), "pressed");
    }

    function test_resolve_state_focus_only_wins_when_focusable() {
        compare(Tokens.resolveState({ focused: true, focusable: true, hovered: true }), "focus");
        compare(Tokens.resolveState({ focused: true, focusable: false, hovered: true }), "hover-cursor");
    }

    function test_resolve_state_hover_cursor_beats_selected() {
        compare(Tokens.resolveState({ hovered: true, selected: true }), "hover-cursor");
    }

    function test_resolve_state_selected_beats_normal() {
        compare(Tokens.resolveState({ selected: true }), "selected");
    }

    function test_resolve_state_defaults_to_normal() {
        compare(Tokens.resolveState({}), "normal");
        compare(Tokens.resolveState(), "normal");
    }

    // 1.2 border specs

    function test_border_spec_defaults_widths_to_given_default() {
        var spec = Tokens.borderSpec("#ffffff", {}, 2);
        compare(spec.widths.top, 2);
        compare(spec.widths.right, 2);
        compare(spec.widths.bottom, 2);
        compare(spec.widths.left, 2);
        compare(spec.gradient.enabled, false);
    }

    function test_border_spec_per_side_override() {
        var spec = Tokens.borderSpec("#ffffff", { top: 0 }, 2);
        compare(spec.widths.top, 0);
        compare(spec.widths.bottom, 2);
    }

    function test_uniform_border_spec_matches_all_sides() {
        var spec = Tokens.uniformBorderSpec("#ffffff", 2);
        verify(Tokens.isUniformBorder(spec));
    }

    function test_is_uniform_border_false_when_sides_differ() {
        var spec = Tokens.borderSpec("#ffffff", { top: 0 }, 2);
        verify(!Tokens.isUniformBorder(spec));
    }

    function test_is_uniform_border_false_when_gradient_enabled() {
        var spec = Tokens.uniformBorderSpec("#ffffff", 2);
        spec.gradient.enabled = true;
        verify(!Tokens.isUniformBorder(spec));
    }

    // selection inversion

    function test_inverted_pair_plain() {
        var colors = { foreground: "#CECDC3", background: "#100F0F", accent: "#4385BE", onAccent: "#FFFCF0" };
        var pair = Tokens.invertedPair(colors, false);
        compare(pair.bg, colors.foreground);
        compare(pair.fg, colors.background);
    }

    function test_inverted_pair_accent() {
        var colors = { foreground: "#CECDC3", background: "#100F0F", accent: "#4385BE", onAccent: "#FFFCF0" };
        var pair = Tokens.invertedPair(colors, true);
        compare(pair.bg, colors.accent);
        compare(pair.fg, colors.onAccent);
    }
}

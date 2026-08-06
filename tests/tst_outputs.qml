import QtQuick
import QtTest
import "../shell/Display/outputs.js" as Outputs

TestCase {
    name: "Outputs"

    function _row(overrides) {
        var row = {
            name: "eDP-1", make: "", model: "",
            x: 0, y: 0, width: 1920, height: 1080, refresh: 60,
            scale: 1, enabled: true, mirrorOf: ""
        };
        for (var key in overrides)
            row[key] = overrides[key];
        return row;
    }

    // scale

    function test_clamp_scale_holds_the_slider_range() {
        compare(Outputs.clampScale(0.4), 1);
        compare(Outputs.clampScale(9), 3);
        compare(Outputs.clampScale(1.75), 1.75);
    }

    function test_clamp_scale_falls_back_on_a_non_number() {
        compare(Outputs.clampScale("wat"), 1);
    }

    function test_quantize_scale_snaps_to_the_quarter_grid() {
        compare(Outputs.quantizeScale(1.6), 1.5);
        compare(Outputs.quantizeScale(1.7), 1.75);
        compare(Outputs.quantizeScale(2), 2);
    }

    function test_fraction_for_scale_spans_the_track() {
        compare(Outputs.fractionForScale(1), 0);
        compare(Outputs.fractionForScale(2), 0.5);
        compare(Outputs.fractionForScale(3), 1);
    }

    function test_scale_for_fraction_quantizes_and_clamps() {
        compare(Outputs.scaleForFraction(0), 1);
        compare(Outputs.scaleForFraction(0.5), 2);
        compare(Outputs.scaleForFraction(1), 3);
        compare(Outputs.scaleForFraction(-4), 1);
        compare(Outputs.scaleForFraction(4), 3);
    }

    // An off-grid live scale steps onto the grid rather than staying off it.
    function test_step_scale_moves_one_notch_from_an_off_grid_value() {
        compare(Outputs.stepScale(1.6, 1), 1.75);
        compare(Outputs.stepScale(1.6, -1), 1.25);
    }

    function test_step_scale_stops_at_the_range_ends() {
        compare(Outputs.stepScale(1, -1), 1);
        compare(Outputs.stepScale(3, 1), 3);
    }

    function test_format_scale_drops_trailing_zeros() {
        compare(Outputs.formatScale(1), "1X");
        compare(Outputs.formatScale(1.5), "1.5X");
        compare(Outputs.formatScale(1.25), "1.25X");
    }

    function test_format_scale_empty_for_a_missing_value() {
        compare(Outputs.formatScale(0), "");
        compare(Outputs.formatScale(undefined), "");
    }

    // cleanScale — Hyprland's whole-logical-pixel constraint

    function test_clean_scale_rounds_up_to_a_divisor_of_the_mode() {
        // gcd(1920*120, 1080*120) = 120*gcd(1920,1080) = 120*120 = 14400;
        // 1.6 -> k=192, which already divides 14400, so it survives intact.
        compare(Outputs.cleanScale(1.6, 1920, 1080), 1.6);
    }

    function test_clean_scale_moves_an_unrepresentable_scale_up() {
        // gcd(1366*120, 768*120) = 120*gcd(1366,768) = 120*2 = 240;
        // 1.25 -> k=150, and the next divisor of 240 at or above it is 240.
        compare(Outputs.cleanScale(1.25, 1366, 768), 2);
    }

    function test_clean_scale_passes_through_when_the_mode_is_unknown() {
        compare(Outputs.cleanScale(1.5, 0, 0), 1.5);
    }

    // sortOutputs

    function test_sort_puts_enabled_outputs_first_then_left_to_right() {
        var rows = Outputs.sortOutputs([
            _row({ name: "HDMI-A-1", enabled: false }),
            _row({ name: "DP-2", x: 3840 }),
            _row({ name: "DP-1", x: 1920 }),
            _row({ name: "eDP-1", x: 0 })
        ]);
        compare(rows.map(function (r) { return r.name; }).join("|"), "eDP-1|DP-1|DP-2|HDMI-A-1");
    }

    function test_sort_breaks_position_ties_by_name() {
        var rows = Outputs.sortOutputs([
            _row({ name: "DP-2" }),
            _row({ name: "DP-1" })
        ]);
        compare(rows[0].name, "DP-1");
    }

    // canToggle

    function test_can_toggle_refuses_to_disable_the_last_enabled_output() {
        var rows = [_row({ name: "eDP-1" }), _row({ name: "DP-1", enabled: false })];
        compare(Outputs.canToggle(rows, "eDP-1"), false);
    }

    function test_can_toggle_always_allows_enabling() {
        var rows = [_row({ name: "eDP-1" }), _row({ name: "DP-1", enabled: false })];
        compare(Outputs.canToggle(rows, "DP-1"), true);
    }

    function test_can_toggle_allows_disabling_when_another_stays_on() {
        var rows = [_row({ name: "eDP-1" }), _row({ name: "DP-1", x: 1920 })];
        compare(Outputs.canToggle(rows, "eDP-1"), true);
    }

    function test_can_toggle_false_for_an_unknown_output() {
        compare(Outputs.canToggle([_row({})], "DP-9"), false);
    }

    // labels

    function test_mode_label_reports_the_current_mode() {
        compare(Outputs.modeLabel(_row({ width: 2560, height: 1440, refresh: 59.951 })), "2560x1440@59.95");
    }

    function test_mode_label_empty_for_a_disabled_output() {
        compare(Outputs.modeLabel(_row({ enabled: false, width: 0, height: 0, refresh: 0 })), "");
    }

    function test_status_line_reports_mode_then_scale() {
        compare(Outputs.statusLine(_row({ width: 2560, height: 1440, refresh: 60, scale: 1.5 })),
                "2560x1440@60 / 1.5X");
    }

    function test_status_line_names_the_mirror_source() {
        compare(Outputs.statusLine(_row({ name: "DP-1", mirrorOf: "eDP-1" })),
                "1920x1080@60 / 1X / MIRRORS eDP-1");
    }

    function test_status_line_of_a_disabled_output_claims_nothing_else() {
        compare(Outputs.statusLine(_row({ enabled: false, width: 0, height: 0, refresh: 0 })), "DISABLED");
    }

    function test_describe_joins_make_and_model() {
        compare(Outputs.describe(_row({ make: "Dell", model: "U2720Q" })), "Dell U2720Q");
    }

    function test_describe_empty_when_the_compositor_reports_neither() {
        compare(Outputs.describe(_row({})), "");
    }

    // mirror

    function test_mirror_plan_points_every_other_output_at_the_focused_one() {
        var rows = [_row({ name: "eDP-1" }), _row({ name: "DP-1", x: 1920 }), _row({ name: "DP-2", x: 3840 })];
        var plan = Outputs.mirrorPlan(rows, "DP-1");
        compare(plan.ok, true);
        compare(plan.primary, "DP-1");
        compare(plan.targets.join("|"), "eDP-1|DP-2");
    }

    function test_mirror_plan_falls_back_to_the_first_sorted_output() {
        var rows = [_row({ name: "DP-1", x: 1920 }), _row({ name: "eDP-1", x: 0 })];
        var plan = Outputs.mirrorPlan(rows, "");
        compare(plan.primary, "eDP-1");
        compare(plan.targets.join("|"), "DP-1");
    }

    function test_mirror_plan_skips_disabled_outputs_entirely() {
        var rows = [_row({ name: "eDP-1" }), _row({ name: "DP-1", enabled: false })];
        var plan = Outputs.mirrorPlan(rows, "eDP-1");
        compare(plan.ok, false);
        compare(plan.reason, "single");
        compare(plan.targets.length, 0);
    }

    function test_mirrored_names_lists_only_the_mirroring_outputs() {
        var rows = [_row({ name: "eDP-1" }), _row({ name: "DP-1", mirrorOf: "eDP-1" })];
        compare(Outputs.mirroredNames(rows).join("|"), "DP-1");
    }

    function test_mirror_source_reports_what_the_mirror_points_at() {
        var rows = [_row({ name: "eDP-1" }), _row({ name: "DP-1", mirrorOf: "eDP-1" })];
        compare(Outputs.mirrorSource(rows), "eDP-1");
    }

    function test_mirror_source_empty_when_nothing_mirrors() {
        compare(Outputs.mirrorSource([_row({})]), "");
    }

    // normalizeNiriOutputs

    function test_normalize_niri_reads_the_current_mode_and_logical_output() {
        var rows = Outputs.normalizeNiriOutputs({
            "eDP-1": {
                name: "eDP-1", make: "Sharp", model: "LQ140M1",
                modes: [
                    { width: 1920, height: 1080, refresh_rate: 60000, is_preferred: false },
                    { width: 2560, height: 1440, refresh_rate: 59951, is_preferred: true }
                ],
                current_mode: 1,
                logical: { x: 0, y: 0, width: 1707, height: 960, scale: 1.5, transform: "Normal" }
            }
        });
        compare(rows.length, 1);
        compare(rows[0].name, "eDP-1");
        compare(rows[0].make, "Sharp");
        compare(rows[0].width, 2560);
        compare(rows[0].height, 1440);
        compare(rows[0].refresh, 59.951);
        compare(rows[0].scale, 1.5);
        compare(rows[0].enabled, true);
    }

    // `logical: null` is niri's own disabled marker, and a disabled output
    // reports a zero mode rather than the last one it happened to run.
    function test_normalize_niri_treats_a_null_logical_output_as_disabled() {
        var rows = Outputs.normalizeNiriOutputs({
            "HDMI-A-1": {
                name: "HDMI-A-1", make: "", model: "",
                modes: [{ width: 1920, height: 1080, refresh_rate: 60000, is_preferred: true }],
                current_mode: null,
                logical: null
            }
        });
        compare(rows[0].enabled, false);
        compare(rows[0].width, 0);
        compare(rows[0].height, 0);
        compare(rows[0].refresh, 0);
    }

    // niri has no mirroring primitive, so no niri row ever claims one.
    function test_normalize_niri_never_reports_a_mirror() {
        var rows = Outputs.normalizeNiriOutputs({
            "eDP-1": { name: "eDP-1", modes: [], current_mode: null, logical: null }
        });
        compare(rows[0].mirrorOf, "");
    }

    function test_normalize_niri_sorts_enabled_first() {
        var rows = Outputs.normalizeNiriOutputs({
            "HDMI-A-1": { name: "HDMI-A-1", modes: [], current_mode: null, logical: null },
            "eDP-1": {
                name: "eDP-1", modes: [{ width: 1920, height: 1080, refresh_rate: 60000 }],
                current_mode: 0, logical: { x: 0, y: 0, width: 1920, height: 1080, scale: 1 }
            }
        });
        compare(rows.map(function (r) { return r.name; }).join("|"), "eDP-1|HDMI-A-1");
    }

    function test_normalize_niri_empty_payload() {
        compare(Outputs.normalizeNiriOutputs(null).length, 0);
        compare(Outputs.normalizeNiriOutputs({}).length, 0);
    }

    // parseHyprlandOutputs

    function test_parse_hyprland_reads_disabled_and_mirror_state() {
        var rows = Outputs.parseHyprlandOutputs(JSON.stringify([
            { name: "eDP-1", make: "Sharp", model: "LQ140M1", x: 0, y: 0, width: 2560, height: 1440, refreshRate: 59.951, scale: 1.5, disabled: false, mirrorOf: "none" },
            { name: "DP-1", make: "Dell", model: "U2720Q", x: 2560, y: 0, width: 3840, height: 2160, refreshRate: 60, scale: 2, disabled: false, mirrorOf: "eDP-1" },
            { name: "HDMI-A-1", x: 0, y: 0, width: 0, height: 0, refreshRate: 0, scale: 1, disabled: true, mirrorOf: "none" }
        ]));
        compare(rows.map(function (r) { return r.name; }).join("|"), "eDP-1|DP-1|HDMI-A-1");
        compare(rows[0].mirrorOf, "");
        compare(rows[0].scale, 1.5);
        compare(rows[1].mirrorOf, "eDP-1");
        compare(rows[2].enabled, false);
    }

    function test_parse_hyprland_drops_a_nameless_entry() {
        var rows = Outputs.parseHyprlandOutputs(JSON.stringify([{ width: 1920, height: 1080 }]));
        compare(rows.length, 0);
    }

    function test_parse_hyprland_malformed_json() {
        compare(Outputs.parseHyprlandOutputs("not json{{{").length, 0);
    }

    function test_parse_hyprland_non_array_payload() {
        compare(Outputs.parseHyprlandOutputs(JSON.stringify({ name: "eDP-1" })).length, 0);
    }

    // hyprlandMonitorArg

    function test_hyprland_arg_restates_the_row_and_applies_the_scale() {
        var arg = Outputs.hyprlandMonitorArg(_row({ name: "DP-1", width: 3840, height: 2160, refresh: 60 }), { scale: 2 });
        compare(arg, "DP-1,3840x2160@60,auto,2");
    }

    // A scale change must not silently drop an active mirror, and a mirror
    // change must not silently reset the scale.
    function test_hyprland_arg_carries_an_existing_mirror_through_a_scale_change() {
        var arg = Outputs.hyprlandMonitorArg(_row({ name: "DP-1", mirrorOf: "eDP-1" }), { scale: 2 });
        compare(arg, "DP-1,1920x1080@60,auto,2,mirror,eDP-1");
    }

    function test_hyprland_arg_keeps_the_scale_through_a_mirror_change() {
        var arg = Outputs.hyprlandMonitorArg(_row({ name: "DP-1", scale: 1.5 }), { mirrorOf: "eDP-1" });
        compare(arg, "DP-1,1920x1080@60,auto,1.5,mirror,eDP-1");
    }

    function test_hyprland_arg_clears_a_mirror_with_an_empty_source() {
        var arg = Outputs.hyprlandMonitorArg(_row({ name: "DP-1", mirrorOf: "eDP-1" }), { mirrorOf: "" });
        compare(arg, "DP-1,1920x1080@60,auto,1");
    }

    function test_hyprland_arg_falls_back_to_preferred_without_a_mode() {
        var arg = Outputs.hyprlandMonitorArg(_row({ name: "DP-1", width: 0, height: 0, refresh: 0 }), {});
        compare(arg, "DP-1,preferred,auto,1");
    }
}

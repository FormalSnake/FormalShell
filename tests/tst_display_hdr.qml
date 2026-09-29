import QtQuick
import QtTest
import "../shell/Display/hdr.js" as Hdr
import "../shell/Display/outputs.js" as Outputs

TestCase {
    name: "DisplayHdr"

    function _row(overrides) {
        var row = {
            name: "eDP-1", make: "", model: "",
            x: 0, y: 0, width: 2560, height: 1600, refresh: 165,
            scale: 1.6, enabled: true, mirrorOf: "",
            transform: 0, vrr: false, cm: "srgb", tenBit: false,
            sdrBrightness: 1, sdrSaturation: 1
        };
        for (var key in overrides)
            row[key] = overrides[key];
        return row;
    }

    function _hex(bytes) {
        return bytes.map(function (b) { return (b < 16 ? "0" : "") + b.toString(16); }).join(" ");
    }

    // A base block plus one CTA-861 extension carrying the given data blocks.
    function _edid(dataBlocks) {
        var base = [];
        for (var i = 0; i < 128; i++)
            base.push(0);
        base[126] = 1;
        var ext = [0x02, 0x03, 0, 0];
        for (var b = 0; b < dataBlocks.length; b++)
            ext = ext.concat(dataBlocks[b]);
        ext[2] = ext.length;
        while (ext.length < 128)
            ext.push(0);
        return _hex(base.concat(ext));
    }

    // Colorimetry: extended tag 7, length 3, ext 5, BT2020 RGB in bit 7.
    readonly property var colorimetry: [0xe3, 0x05, 0xc0, 0x00]
    // HDR static metadata: ext 6, EOTF byte with PQ (bit 2), descriptor
    // byte, max luminance code 96 (50 * 2^3 = 400 nits).
    readonly property var hdrStatic: [0xe6, 0x06, 0x05, 0x01, 96, 96, 0]

    function test_edid_with_pq_and_bt2020_is_supported() {
        var edid = Hdr.parseEdid(_edid([colorimetry, hdrStatic]));
        compare(edid.present, true);
        compare(edid.wide, true);
        compare(edid.pq, true);
        compare(edid.maxNits, 400);
        compare(Hdr.verdict(edid).supported, true);
    }

    function test_edid_without_a_static_metadata_block_says_no_hdr() {
        var v = Hdr.verdict(Hdr.parseEdid(_edid([colorimetry])));
        compare(v.supported, false);
        compare(v.reason, "No HDR in EDID");
    }

    function test_edid_with_hlg_only_is_not_pq() {
        var hlgOnly = [0xe6, 0x06, 0x09, 0x01, 96, 96, 0];
        compare(Hdr.verdict(Hdr.parseEdid(_edid([colorimetry, hlgOnly]))).reason, "No HDR in EDID");
    }

    function test_edid_with_pq_but_no_bt2020_says_no_wide_gamut() {
        var v = Hdr.verdict(Hdr.parseEdid(_edid([hdrStatic])));
        compare(v.supported, false);
        compare(v.reason, "No wide gamut in EDID");
    }

    function test_empty_or_truncated_edid_is_not_present() {
        compare(Hdr.verdict(Hdr.parseEdid("")).reason, "No EDID");
        compare(Hdr.verdict(Hdr.parseEdid("00 ff ff")).reason, "No EDID");
        compare(Hdr.verdict(undefined).reason, "No EDID");
    }

    function test_dump_splits_connectors_and_prefers_a_populated_node() {
        var good = _edid([colorimetry, hdrStatic]);
        var text = "@@eDP-1\n" + good + "\n@@DP-2\n@@eDP-1\n" + good + "\n";
        var dump = Hdr.parseDump(text);
        compare(dump["DP-2"].present, false);
        compare(dump["eDP-1"].pq, true);
        var twice = Hdr.parseDump("@@eDP-1\n" + good + "\n@@eDP-1\n\n");
        compare(twice["eDP-1"].pq, true);
    }

    // The rule for the current monitor must restate what monitors -j says.
    function test_color_rule_keeps_mode_position_scale_transform_vrr() {
        var row = _row({ x: 1920, y: 240, transform: 1, vrr: true, scale: 1.67 });
        var rule = Outputs.hyprlandColorRule(row, Hdr.onColor(1.2, 1));
        compare(rule.output, "eDP-1");
        compare(rule.mode, "2560x1600@165");
        compare(rule.position, "1920x240");
        compare(rule.scale, "1.66667");
        compare(rule.transform, 1);
        compare(rule.vrr, 1);
        compare(rule.bitdepth, 10);
        compare(rule.cm, "hdr");
        compare(rule.sdrbrightness, "1.2");
        verify(rule.mirror === undefined);
    }

    function test_color_rule_does_not_clamp_a_live_scale_below_one() {
        var rule = Outputs.hyprlandColorRule(_row({ scale: 0.8 }), Hdr.onColor(1, 1));
        compare(rule.scale, "0.8");
    }

    function test_color_rule_carries_a_mirror() {
        var rule = Outputs.hyprlandColorRule(_row({ mirrorOf: "DP-1" }), Hdr.onColor(1, 1));
        compare(rule.mirror, "DP-1");
        verify(Outputs.hyprlandRuleArg(rule).indexOf(",mirror,DP-1") > 0);
    }

    function test_rule_arg_is_the_hyprlang_monitor_line() {
        var rule = Outputs.hyprlandColorRule(_row({ scale: 1 }), Hdr.onColor(1.2, 1));
        compare(Outputs.hyprlandRuleArg(rule),
            "eDP-1,2560x1600@165,0x0,1,transform,0,vrr,0,bitdepth,10,cm,hdr,sdrbrightness,1.2,sdrsaturation,1");
    }

    function test_rule_lua_is_an_hl_monitor_call() {
        var rule = Outputs.hyprlandColorRule(_row({ scale: 1 }), Hdr.onColor(1.2, 1));
        compare(Outputs.hyprlandRuleLua(rule),
            "hl.monitor({ output = \"eDP-1\", mode = \"2560x1600@165\", position = \"0x0\", scale = 1, transform = 0, vrr = 0, bitdepth = 10, cm = \"hdr\", sdrbrightness = 1.2, sdrsaturation = 1 })");
    }

    // A scale or mirror change on an output in HDR must not drop HDR.
    function test_scale_change_keeps_an_active_hdr_preset() {
        var arg = Outputs.hyprlandMonitorArg(_row({ cm: "hdr", tenBit: true, sdrBrightness: 1.2 }), { scale: 2 });
        verify(arg.indexOf(",bitdepth,10,cm,hdr,sdrbrightness,1.2,sdrsaturation,1") > 0);
    }

    function test_parse_reads_the_colour_fields() {
        var rows = Outputs.parseHyprlandOutputs(JSON.stringify([{
            name: "eDP-1", x: 0, y: 0, width: 2560, height: 1600, refreshRate: 165, scale: 1.6,
            transform: 3, vrr: true, currentFormat: "XRGB2101010", colorManagementPreset: "hdr",
            sdrBrightness: 1.2, sdrSaturation: 0.98, mirrorOf: "none"
        }]));
        compare(rows[0].transform, 3);
        compare(rows[0].vrr, true);
        compare(rows[0].tenBit, true);
        compare(rows[0].cm, "hdr");
        compare(rows[0].sdrBrightness, 1.2);
    }

    function test_off_color_restores_the_prior_and_never_an_hdr_preset() {
        var prior = Hdr.priorOf(_row({ cm: "wide", tenBit: true }));
        compare(prior.cm, "wide");
        compare(prior.bitdepth, 10);
        compare(Hdr.offColor(prior).cm, "wide");
        compare(Hdr.priorOf(_row({ cm: "hdr", tenBit: true })).cm, "srgb");
        compare(Hdr.offColor({ cm: "hdr" }).cm, "srgb");
        compare(Hdr.offColor(null).bitdepth, 8);
    }

    function test_state_helpers_return_fresh_objects() {
        var a = Hdr.withOutput(null, "eDP-1", { cm: "srgb" });
        verify(a["eDP-1"] !== undefined);
        var b = Hdr.withoutOutput(a, "eDP-1");
        verify(b["eDP-1"] === undefined);
        verify(a["eDP-1"] !== undefined);
        compare(Object.keys(Hdr.stateOf("junk")).length, 0);
        compare(Object.keys(Hdr.stateOf({ x: 1, y: { prior: {} } })).join(), "y");
    }

    function test_reapply_wants_only_supported_lit_outputs_not_in_hdr_and_untried() {
        var saved = { "eDP-1": { prior: {} }, "DP-1": { prior: {} }, "DP-2": { prior: {} }, "DP-3": { prior: {} } };
        var rows = [
            _row({ name: "eDP-1" }),
            _row({ name: "DP-1" }),
            _row({ name: "DP-2", cm: "hdr" }),
            _row({ name: "DP-3", enabled: false }),
            _row({ name: "DP-4" })
        ];
        var verdicts = {
            "eDP-1": { supported: true }, "DP-1": { supported: false },
            "DP-2": { supported: true }, "DP-3": { supported: true }, "DP-4": { supported: true }
        };
        compare(Hdr.pendingReapply(saved, rows, verdicts, {}).join(), "eDP-1");
        compare(Hdr.pendingReapply(saved, rows, verdicts, { "eDP-1": true }).length, 0);
        compare(Hdr.pendingReapply(null, rows, verdicts, {}).length, 0);
    }
}

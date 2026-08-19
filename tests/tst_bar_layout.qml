import QtQuick
import QtTest
import "../shell/Bar/layout.js" as Layout

TestCase {
    name: "BarLayout"

    function names(entries) {
        return entries.map(function (e) { return e.kind === "builtin" ? e.name : "custom:" + e.id; }).join(",");
    }

    function test_default_fallback_when_bar_is_undefined() {
        var r = Layout.resolve(undefined);
        compare(names(r.regions.left), "launcher,workspaces,activeWindow");
        compare(names(r.regions.center), "clock,nowPlaying");
        compare(names(r.regions.right), "battery,audio,network,bluetooth,weather,tray,bell,indicators");
        compare(r.warnings.length, 0);
    }

    function test_default_fallback_when_layout_key_missing() {
        var r = Layout.resolve({});
        compare(names(r.regions.left), "launcher,workspaces,activeWindow");
        compare(names(r.regions.right), "battery,audio,network,bluetooth,weather,tray,bell,indicators");
    }

    function test_partial_layout_falls_back_per_region() {
        var r = Layout.resolve({ layout: { left: ["clock"] } });
        compare(names(r.regions.left), "clock");
        compare(names(r.regions.center), "clock,nowPlaying");
        compare(names(r.regions.right), "battery,audio,network,bluetooth,weather,tray,bell,indicators");
    }

    function test_custom_order_is_preserved() {
        var r = Layout.resolve({ layout: { left: ["activeWindow", "workspaces"] } });
        compare(names(r.regions.left), "activeWindow,workspaces");
    }

    function test_empty_region_stays_empty() {
        var r = Layout.resolve({ layout: { right: [] } });
        compare(r.regions.right.length, 0);
        compare(r.warnings.length, 0);
    }

    function test_unknown_widget_name_is_skipped_with_warning() {
        var r = Layout.resolve({ layout: { left: ["workspaces", "notreal"] } });
        compare(names(r.regions.left), "workspaces");
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("notreal") >= 0);
    }

    function test_custom_module_resolves_to_its_definition() {
        var mod = { id: "disk", type: "command", command: ["echo", "hi"] };
        var r = Layout.resolve({ layout: { right: ["custom:disk"] }, modules: [mod] });
        compare(r.regions.right.length, 1);
        compare(r.regions.right[0].kind, "module");
        compare(r.regions.right[0].id, "disk");
        compare(r.regions.right[0].module, mod);
        compare(r.warnings.length, 0);
    }

    function test_unknown_module_reference_is_skipped_with_warning() {
        var r = Layout.resolve({ layout: { right: ["custom:missing"] }, modules: [] });
        compare(r.regions.right.length, 0);
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("missing") >= 0);
    }

    function test_module_with_unknown_type_is_skipped_with_warning() {
        var mod = { id: "bad", type: "shellscript" };
        var r = Layout.resolve({ layout: { right: ["custom:bad"] }, modules: [mod] });
        compare(r.regions.right.length, 0);
        compare(r.warnings.length, 1);
    }

    function test_github_is_an_optin_builtin_absent_from_defaults() {
        var r = Layout.resolve({ layout: { right: ["github"] } });
        compare(names(r.regions.right), "github");
        compare(r.warnings.length, 0);
        var d = Layout.resolve(undefined);
        verify(names(d.regions.left).indexOf("github") < 0);
        verify(names(d.regions.center).indexOf("github") < 0);
        verify(names(d.regions.right).indexOf("github") < 0);
    }

    function test_usage_is_an_optin_builtin_absent_from_defaults() {
        var r = Layout.resolve({ layout: { right: ["usage"] } });
        compare(names(r.regions.right), "usage");
        compare(r.warnings.length, 0);
        var d = Layout.resolve(undefined);
        verify(names(d.regions.left).indexOf("usage") < 0);
        verify(names(d.regions.center).indexOf("usage") < 0);
        verify(names(d.regions.right).indexOf("usage") < 0);
    }

    function test_tailscale_is_an_optin_builtin_absent_from_defaults() {
        var r = Layout.resolve({ layout: { right: ["tailscale"] } });
        compare(names(r.regions.right), "tailscale");
        compare(r.warnings.length, 0);
        var d = Layout.resolve(undefined);
        verify(names(d.regions.left).indexOf("tailscale") < 0);
        verify(names(d.regions.center).indexOf("tailscale") < 0);
        verify(names(d.regions.right).indexOf("tailscale") < 0);
    }

    function test_visualizer_is_an_optin_builtin_absent_from_defaults() {
        var r = Layout.resolve({ layout: { right: ["visualizer"] } });
        compare(names(r.regions.right), "visualizer");
        compare(r.warnings.length, 0);
        var d = Layout.resolve(undefined);
        verify(names(d.regions.left).indexOf("visualizer") < 0);
        verify(names(d.regions.center).indexOf("visualizer") < 0);
        verify(names(d.regions.right).indexOf("visualizer") < 0);
    }

    function test_microphone_is_an_optin_builtin_absent_from_defaults() {
        var r = Layout.resolve({ layout: { right: ["microphone"] } });
        compare(names(r.regions.right), "microphone");
        compare(r.warnings.length, 0);
        var d = Layout.resolve(undefined);
        verify(names(d.regions.left).indexOf("microphone") < 0);
        verify(names(d.regions.center).indexOf("microphone") < 0);
        verify(names(d.regions.right).indexOf("microphone") < 0);
    }

    function test_keyboard_layout_is_an_optin_builtin_absent_from_defaults() {
        var r = Layout.resolve({ layout: { right: ["keyboardLayout"] } });
        compare(names(r.regions.right), "keyboardLayout");
        compare(r.warnings.length, 0);
        var d = Layout.resolve(undefined);
        verify(names(d.regions.left).indexOf("keyboardLayout") < 0);
        verify(names(d.regions.center).indexOf("keyboardLayout") < 0);
        verify(names(d.regions.right).indexOf("keyboardLayout") < 0);
    }

    function test_system_update_is_an_optin_builtin_absent_from_defaults() {
        var r = Layout.resolve({ layout: { right: ["systemUpdate"] } });
        compare(names(r.regions.right), "systemUpdate");
        compare(r.warnings.length, 0);
        var d = Layout.resolve(undefined);
        verify(names(d.regions.left).indexOf("systemUpdate") < 0);
        verify(names(d.regions.center).indexOf("systemUpdate") < 0);
        verify(names(d.regions.right).indexOf("systemUpdate") < 0);
    }

    function test_airpods_is_an_optin_builtin_absent_from_defaults() {
        var r = Layout.resolve({ layout: { right: ["airpods"] } });
        compare(names(r.regions.right), "airpods");
        compare(r.warnings.length, 0);
        var d = Layout.resolve(undefined);
        verify(names(d.regions.left).indexOf("airpods") < 0);
        verify(names(d.regions.center).indexOf("airpods") < 0);
        verify(names(d.regions.right).indexOf("airpods") < 0);
    }

    function test_display_is_an_optin_builtin_absent_from_defaults() {
        var r = Layout.resolve({ layout: { right: ["display"] } });
        compare(names(r.regions.right), "display");
        compare(r.warnings.length, 0);
        var d = Layout.resolve(undefined);
        verify(names(d.regions.left).indexOf("display") < 0);
        verify(names(d.regions.center).indexOf("display") < 0);
        verify(names(d.regions.right).indexOf("display") < 0);
    }

    function test_monitor_is_an_optin_builtin_absent_from_defaults() {
        var r = Layout.resolve({ layout: { right: ["monitor"] } });
        compare(names(r.regions.right), "monitor");
        compare(r.warnings.length, 0);
        var d = Layout.resolve(undefined);
        verify(names(d.regions.left).indexOf("monitor") < 0);
        verify(names(d.regions.center).indexOf("monitor") < 0);
        verify(names(d.regions.right).indexOf("monitor") < 0);
    }

    function test_bell_is_a_default_builtin_before_indicators() {
        var r = Layout.resolve(undefined);
        var right = names(r.regions.right).split(",");
        var bell = right.indexOf("bell");
        verify(bell >= 0);
        compare(right[bell + 1], "indicators");
    }

    function test_custom_module_id_never_collides_with_builtin_name() {
        var mod = { id: "clock", type: "command", command: ["echo", "hi"] };
        var r = Layout.resolve({ layout: { center: ["clock", "custom:clock"] }, modules: [mod] });
        compare(r.regions.center.length, 2);
        compare(r.regions.center[0].kind, "builtin");
        compare(r.regions.center[1].kind, "module");
    }

    // A resolved record exactly as shell/Plugins/manifest.js emits one: every
    // optional key already defaulted, keys with no meaning for the kind null.
    function barPlugin(id, region) {
        return {
            id: id, kind: "bar", entry: "E.qml", dir: "/p/" + id, name: id,
            region: region, keepLoaded: null, width: null,
            entryUrl: "file:///p/" + id + "/E.qml"
        };
    }

    function test_plugin_resolves_to_its_manifest() {
        var p = barPlugin("diskwatch", "right");
        var r = Layout.resolve({ layout: { right: ["plugin:diskwatch"] } }, [p]);
        compare(r.regions.right.length, 1);
        compare(r.regions.right[0].kind, "plugin");
        compare(r.regions.right[0].id, "diskwatch");
        compare(r.regions.right[0].plugin, p);
        compare(r.warnings.length, 0);
    }

    function test_unknown_plugin_reference_is_skipped_with_warning() {
        var r = Layout.resolve({ layout: { right: ["plugin:missing"] } }, []);
        compare(r.regions.right.length, 0);
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("missing") >= 0);
    }

    function test_plugin_id_never_collides_with_builtin_name() {
        var p = barPlugin("clock", "center");
        var r = Layout.resolve({ layout: { center: ["clock", "plugin:clock"] } }, [p]);
        compare(r.regions.center.length, 2);
        compare(r.regions.center[0].kind, "builtin");
        compare(r.regions.center[1].kind, "plugin");
    }

    function test_unnamed_bar_plugin_auto_appends_to_its_region() {
        var p = barPlugin("diskwatch", "left");
        var r = Layout.resolve(undefined, [p]);
        compare(r.regions.left.length, 4);
        compare(r.regions.left[3].kind, "plugin");
        compare(r.regions.left[3].id, "diskwatch");
        compare(r.warnings.length, 0);
    }

    function test_explicitly_placed_plugin_is_not_also_appended() {
        var p = barPlugin("diskwatch", "left");
        var r = Layout.resolve({ layout: { right: ["plugin:diskwatch"] } }, [p]);
        compare(r.regions.left.length, 3);
        compare(r.regions.right.length, 1);
        compare(r.regions.right[0].id, "diskwatch");
    }

    // M24: the chevron is a collapse boundary, its position is its whole
    // configuration, and every rule that keeps it from being a dead control
    // lives in the resolver rather than in the widget. M25: which side it
    // governs follows the region, inward from the region's anchored edge, so
    // the chevron itself keeps its x when the group opens.
    function collapsible(entries) {
        return entries.map(function (e) { return e.collapsible ? "1" : "0"; }).join("");
    }

    function test_governs_before_only_in_the_right_region() {
        verify(Layout.governsBefore("right"));
        verify(!Layout.governsBefore("left"));
        verify(!Layout.governsBefore("center"));
    }

    function test_chevron_is_an_optin_builtin_absent_from_defaults() {
        var r = Layout.resolve({ layout: { right: ["tray", "chevron"] } });
        compare(names(r.regions.right), "tray,chevron");
        compare(r.warnings.length, 0);
        var d = Layout.resolve(undefined);
        verify(names(d.regions.left).indexOf("chevron") < 0);
        verify(names(d.regions.center).indexOf("chevron") < 0);
        verify(names(d.regions.right).indexOf("chevron") < 0);
    }

    function test_no_chevron_leaves_every_entry_uncollapsible() {
        var r = Layout.resolve(undefined);
        compare(collapsible(r.regions.left), "000");
        compare(collapsible(r.regions.center), "00");
        compare(collapsible(r.regions.right), "00000000");
    }

    function test_right_region_chevron_marks_only_what_precedes_it() {
        var r = Layout.resolve({ layout: { right: ["battery", "chevron", "weather", "tray"] } });
        compare(names(r.regions.right), "battery,chevron,weather,tray");
        compare(collapsible(r.regions.right), "1000");
        compare(r.warnings.length, 0);
    }

    function test_left_region_chevron_marks_only_what_follows_it() {
        var r = Layout.resolve({ layout: { left: ["battery", "chevron", "weather", "tray"] } });
        compare(names(r.regions.left), "battery,chevron,weather,tray");
        compare(collapsible(r.regions.left), "0011");
        compare(r.warnings.length, 0);
    }

    function test_center_region_chevron_marks_what_follows_it() {
        var r = Layout.resolve({ layout: { center: ["clock", "chevron", "nowPlaying", "weather"] } });
        compare(collapsible(r.regions.center), "0011");
        compare(r.warnings.length, 0);
    }

    function test_every_entry_carries_its_own_region() {
        var r = Layout.resolve({ layout: { left: ["clock"], center: ["chevron", "clock"] } });
        compare(r.regions.left[0].region, "left");
        compare(r.regions.center[0].region, "center");
        compare(r.regions.center[1].region, "center");
        compare(r.regions.right[0].region, "right");
    }

    // The live half of the two drop cases below: a chevron placed against
    // its region's own anchored edge governs everything else in that region,
    // which is the arrangement M25 exists to produce.
    function test_chevron_against_its_regions_anchored_edge_survives() {
        var r = Layout.resolve({ layout: { right: ["battery", "chevron"], left: ["chevron", "workspaces"] } });
        compare(names(r.regions.right), "battery,chevron");
        compare(collapsible(r.regions.right), "10");
        compare(names(r.regions.left), "chevron,workspaces");
        compare(collapsible(r.regions.left), "01");
        compare(r.warnings.length, 0);
    }

    function test_left_region_chevron_placed_last_is_dropped_with_a_warning() {
        var r = Layout.resolve({ layout: { left: ["workspaces", "chevron"] } });
        compare(names(r.regions.left), "workspaces");
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("nothing after it") >= 0);
        verify(r.warnings[0].indexOf("bar.layout.left") >= 0);
    }

    function test_right_region_chevron_placed_first_is_dropped_with_a_warning() {
        var r = Layout.resolve({ layout: { right: ["chevron", "battery"] } });
        compare(names(r.regions.right), "battery");
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("nothing before it") >= 0);
        verify(r.warnings[0].indexOf("bar.layout.right") >= 0);
    }

    function test_lone_chevron_in_a_region_is_dropped_with_a_warning() {
        var r = Layout.resolve({ layout: { center: ["chevron"], right: ["chevron"] } });
        compare(r.regions.center.length, 0);
        compare(r.regions.right.length, 0);
        compare(r.warnings.length, 2);
        verify(r.warnings[0].indexOf("nothing after it") >= 0);
        verify(r.warnings[1].indexOf("nothing before it") >= 0);
    }

    function test_second_chevron_in_a_region_is_dropped_with_a_warning() {
        var r = Layout.resolve({ layout: { left: ["chevron", "battery", "chevron", "tray"] } });
        compare(names(r.regions.left), "chevron,battery,tray");
        compare(collapsible(r.regions.left), "011");
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("only one chevron per region") >= 0);
    }

    // The dedupe pass runs first, so the survivor can itself end up on the
    // region's anchored edge and has to be dropped by the second pass with
    // its own warning.
    function test_duplicate_chevron_that_leaves_a_dead_survivor_drops_both() {
        var r = Layout.resolve({ layout: { left: ["battery", "chevron", "chevron"] } });
        compare(names(r.regions.left), "battery");
        compare(r.warnings.length, 2);
        verify(r.warnings[0].indexOf("only one chevron per region") >= 0);
        verify(r.warnings[1].indexOf("nothing after it") >= 0);
    }

    function test_right_region_duplicate_chevron_that_leaves_a_dead_survivor_drops_both() {
        var r = Layout.resolve({ layout: { right: ["chevron", "chevron", "battery"] } });
        compare(names(r.regions.right), "battery");
        compare(r.warnings.length, 2);
        verify(r.warnings[0].indexOf("only one chevron per region") >= 0);
        verify(r.warnings[1].indexOf("nothing before it") >= 0);
    }

    function test_chevron_in_one_region_does_not_mark_another() {
        var r = Layout.resolve({ layout: { left: ["chevron", "workspaces", "activeWindow"] } });
        compare(collapsible(r.regions.left), "011");
        compare(collapsible(r.regions.center), "00");
        compare(collapsible(r.regions.right), "00000000");
    }

    // An unnamed bar plugin is appended after everything bar.layout listed,
    // so a left or center chevron written last is only genuinely last once
    // that pass is done.
    function test_auto_appended_plugin_saves_an_otherwise_trailing_chevron() {
        var p = barPlugin("diskwatch", "left");
        var r = Layout.resolve({ layout: { left: ["battery", "chevron"] } }, [p]);
        compare(r.warnings.length, 0);
        compare(r.regions.left.length, 3);
        compare(collapsible(r.regions.left), "001");
    }

    // The same append lands on the wrong side to save a right region's
    // chevron, which governs the other way.
    function test_auto_appended_plugin_cannot_save_a_right_region_chevron() {
        var p = barPlugin("diskwatch", "right");
        var r = Layout.resolve({ layout: { right: ["chevron", "battery"] } }, [p]);
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("nothing before it") >= 0);
        compare(r.regions.right.length, 2);
        compare(collapsible(r.regions.right), "00");
    }

    function test_collapsed_names_reports_layout_names_in_order() {
        var mod = { id: "disk", type: "command", command: ["echo", "hi"] };
        var p = barPlugin("diskwatch", "right");
        var r = Layout.resolve({ layout: { right: ["custom:disk", "plugin:diskwatch", "tray", "chevron", "battery"] }, modules: [mod] }, [p]);
        compare(Layout.collapsedNames(r.regions.right).join(","), "custom:disk,plugin:diskwatch,tray");
        compare(Layout.collapsedNames(r.regions.left).length, 0);
    }

    function test_has_chevron_answers_per_region() {
        var r = Layout.resolve({ layout: { right: ["battery", "chevron", "tray"] } });
        verify(Layout.hasChevron(r.regions.right));
        verify(!Layout.hasChevron(r.regions.left));
        verify(!Layout.hasChevron(r.regions.center));
    }
}

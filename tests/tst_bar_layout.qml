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
        compare(names(r.regions.left), "workspaces,activeWindow");
        compare(names(r.regions.center), "clock,nowPlaying");
        compare(names(r.regions.right), "battery,audio,network,bluetooth,weather,tray,indicators");
        compare(r.warnings.length, 0);
    }

    function test_default_fallback_when_layout_key_missing() {
        var r = Layout.resolve({});
        compare(names(r.regions.left), "workspaces,activeWindow");
        compare(names(r.regions.right), "battery,audio,network,bluetooth,weather,tray,indicators");
    }

    function test_partial_layout_falls_back_per_region() {
        var r = Layout.resolve({ layout: { left: ["clock"] } });
        compare(names(r.regions.left), "clock");
        compare(names(r.regions.center), "clock,nowPlaying");
        compare(names(r.regions.right), "battery,audio,network,bluetooth,weather,tray,indicators");
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

    function test_custom_module_id_never_collides_with_builtin_name() {
        var mod = { id: "clock", type: "command", command: ["echo", "hi"] };
        var r = Layout.resolve({ layout: { center: ["clock", "custom:clock"] }, modules: [mod] });
        compare(r.regions.center.length, 2);
        compare(r.regions.center[0].kind, "builtin");
        compare(r.regions.center[1].kind, "module");
    }
}

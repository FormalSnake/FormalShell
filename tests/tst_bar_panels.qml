import QtQuick
import QtTest
import "../shell/Bar/layout.js" as Layout
import "../shell/Bar/panels.js" as Panels

TestCase {
    name: "BarPanels"

    function at(bar, n) {
        return Panels.panelAt(Layout.resolve(bar), n);
    }

    function test_default_right_region_counts_from_the_centre_out() {
        compare(at(undefined, 1), "power");
        compare(at(undefined, 2), "audio");
        compare(at(undefined, 3), "network");
        compare(at(undefined, 4), "bluetooth");
        compare(at(undefined, 5), "weather");
    }

    function test_out_of_range_is_empty() {
        compare(at(undefined, 6), "");
        compare(at(undefined, 0), "");
        compare(at(undefined, -1), "");
    }

    function test_tray_bell_and_indicators_are_not_counted() {
        var bar = { layout: { right: ["tray", "bell", "indicators", "audio"] } };
        compare(at(bar, 1), "audio");
        compare(at(bar, 2), "");
    }

    function test_chevron_and_the_cells_it_hides_still_count() {
        // layout.js annotates the first four collapsible here (a right
        // region's chevron governs what precedes it), and the count has to
        // be blind to that: the keybind addresses the configured layout.
        var bar = { layout: { right: ["battery", "audio", "network", "bluetooth", "chevron", "weather"] } };
        var resolved = Layout.resolve(bar);
        compare(Layout.collapsedNames(resolved.regions.right).join(","), "battery,audio,network,bluetooth");
        compare(Panels.panelAt(resolved, 1), "power");
        compare(Panels.panelAt(resolved, 4), "bluetooth");
        compare(Panels.panelAt(resolved, 5), "weather");
        compare(Panels.panelAt(resolved, 6), "");
    }

    function test_unknown_widget_names_are_skipped() {
        var bar = { layout: { right: ["notreal", "weather", "alsonotreal", "monitor"] } };
        compare(at(bar, 1), "weather");
        compare(at(bar, 2), "monitor");
        compare(at(bar, 3), "");
    }

    function test_modules_and_activewindow_are_skipped() {
        var bar = {
            layout: { right: ["custom:disk", "activeWindow", "usage"] },
            modules: [{ id: "disk", type: "command", command: ["echo", "hi"] }]
        };
        compare(at(bar, 1), "usage");
        compare(at(bar, 2), "");
    }

    function test_widget_and_panel_names_differ_where_the_registry_does() {
        var bar = { layout: { right: ["battery", "clock", "nowPlaying", "microphone", "systemUpdate"] } };
        compare(at(bar, 1), "power");
        compare(at(bar, 2), "calendar");
        compare(at(bar, 3), "media");
        compare(at(bar, 4), "audio");
        compare(at(bar, 5), "systemupdate");
    }

    function test_only_the_right_region_is_counted() {
        var bar = { layout: { left: ["audio"], center: ["network"], right: ["weather"] } };
        compare(at(bar, 1), "weather");
        compare(at(bar, 2), "");
    }
}

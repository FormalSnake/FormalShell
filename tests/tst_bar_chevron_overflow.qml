import QtQuick
import QtTest
import "../shell/Bar/layout.js" as Layout

// What the chevron's second bar is handed (M52): the governed group, and
// nothing about where it might otherwise have been drawn.
TestCase {
    name: "BarChevronOverflow"

    // The entries the second bar renders: the governed ones alone, with the
    // annotation cleared so Bar.qml's own region delegate draws them there
    // instead of treating them as off-strip again.
    function test_overflow_entries_are_the_group_with_the_gate_cleared() {
        var r = Layout.resolve({ layout: { right: ["bluetooth", "weather", "chevron", "battery", "audio"] } });
        var entries = Layout.overflowEntries(r.regions.right);
        compare(entries.length, 2);
        compare(entries.map(function (e) { return e.name; }).join(","), "bluetooth,weather");
        for (var i = 0; i < entries.length; i++) {
            compare(entries[i].collapsible, false);
            compare(entries[i].region, "right");
            compare(entries[i].kind, "builtin");
        }
        // Copies: the strip's own entries stay annotated, which is what keeps
        // them off it.
        compare(Layout.collapsedNames(r.regions.right).join(","), "bluetooth,weather");
    }

    // A left region governs the other way, and the copies follow the same
    // rule rather than a fixed side.
    function test_the_governed_side_follows_the_region() {
        var r = Layout.resolve({ layout: { left: ["launcher", "chevron", "workspaces", "activeWindow"] } });
        var entries = Layout.overflowEntries(r.regions.left);
        compare(entries.map(function (e) { return e.name; }).join(","), "workspaces,activeWindow");
    }

    function test_a_region_with_no_chevron_has_no_overflow() {
        var r = Layout.resolve({ layout: { right: ["battery", "audio"] } });
        compare(Layout.overflowEntries(r.regions.right).length, 0);
    }

    // A module or plugin entry carries more than a name, and the copy has to
    // keep all of it: the delegate reads `module`/`plugin` back on load.
    function test_a_module_entry_survives_the_copy_whole() {
        var r = Layout.resolve({
            layout: { right: ["custom:cpu", "chevron", "audio"] },
            modules: [{ id: "cpu", type: "command", command: ["true"], interval: 1000 }]
        });
        var entries = Layout.overflowEntries(r.regions.right);
        compare(entries.length, 1);
        compare(entries[0].kind, "module");
        compare(entries[0].id, "cpu");
        compare(entries[0].module.type, "command");
        compare(entries[0].collapsible, false);
    }
}

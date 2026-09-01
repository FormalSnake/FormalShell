import QtQuick
import QtTest
import "../shell/Bar/chevron.js" as ChevronFit
import "../shell/Bar/layout.js" as Layout

// The chevron's room question (M52, Bar/chevron.js), the arithmetic behind a
// group that opens on the strip when it fits and in the second bar when it
// does not.
TestCase {
    name: "BarChevronFit"

    function test_a_group_costs_its_cells_plus_one_gap_each() {
        // Every cell joining a region that already holds one is charged the
        // region's spacing as well as its own extent.
        compare(ChevronFit.groupAlong([30, 40, 50], 8), 144);
        compare(ChevronFit.groupAlong([], 8), 0);
    }

    function test_no_group_always_fits() {
        // A region with no chevron, or one whose governed widgets are all
        // hiding themselves, never has anywhere else to be.
        verify(ChevronFit.fitsInline(0, -400, false));
    }

    function test_room_decides_while_the_group_is_collapsed() {
        verify(ChevronFit.fitsInline(120, 200, false));
        verify(!ChevronFit.fitsInline(120, 40, false));
    }

    // The claim the whole design rests on: the answer does not change when
    // the group moves, so it cannot oscillate. Expanded, the strip's leftover
    // room is smaller by exactly what the group took, and both readings of
    // the same layout agree.
    function test_the_answer_is_the_same_in_either_state() {
        var need = 120;
        var slackCollapsed = 200;
        var slackExpanded = slackCollapsed - need;
        compare(ChevronFit.fitsInline(need, slackExpanded, true),
            ChevronFit.fitsInline(need, slackCollapsed, false));

        slackCollapsed = 40;
        slackExpanded = slackCollapsed - need;
        compare(ChevronFit.fitsInline(need, slackExpanded, true),
            ChevronFit.fitsInline(need, slackCollapsed, false));
    }

    // A group that exactly fills the leftover room is on the strip: the cap
    // the regions clip at is the same number, so nothing is lost.
    function test_an_exact_fit_stays_on_the_strip() {
        verify(ChevronFit.fitsInline(120, 120, false));
    }

    // What the second bar renders: the governed entries alone, with the
    // annotation cleared so Bar.qml's own delegate draws them at full extent
    // there instead of collapsing them again.
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
        // Copies: the strip's own entries still answer to the chevron.
        compare(Layout.collapsedNames(r.regions.right).join(","), "bluetooth,weather");
    }

    function test_a_region_with_no_chevron_has_no_overflow() {
        var r = Layout.resolve({ layout: { right: ["battery", "audio"] } });
        compare(Layout.overflowEntries(r.regions.right).length, 0);
    }
}

import QtQuick
import QtTest
import "../shell/Screensaver/outputs.js" as Outputs

// Which output the screensaver animates. A nested smoke session has exactly
// one output, so the multi-head rules — the priority list's order, its
// fallbacks, and what a plug or an unplug does to a run already going — have
// nowhere else to be proven.
TestCase {
    name: "ScreensaverOutputs"

    readonly property var both: ["eDP-1", "HDMI-A-1"]

    // ---- the priority list

    function test_first_connected_entry_wins() {
        compare(Outputs.resolveMainOutput(both, ["HDMI-A-1", "eDP-1"], "eDP-1", ""), "HDMI-A-1");
        compare(Outputs.resolveMainOutput(both, ["eDP-1", "HDMI-A-1"], "HDMI-A-1", ""), "eDP-1");
    }

    function test_entry_matches_a_port_without_its_index() {
        compare(Outputs.matchEntry(both, "HDMI"), "HDMI-A-1");
        compare(Outputs.matchEntry(["DP-2", "eDP-1"], "DP"), "DP-2");
        // Anchored: "DP" is DisplayPort, never the "eDP" the panel is on.
        compare(Outputs.matchEntry(["eDP-1"], "DP"), "");
    }

    function test_exact_name_beats_a_port_prefix() {
        compare(Outputs.matchEntry(["HDMI-A-2", "HDMI-A-1"], "HDMI-A-1"), "HDMI-A-1");
    }

    function test_internal_and_external_aliases() {
        compare(Outputs.matchEntry(both, "internal"), "eDP-1");
        compare(Outputs.matchEntry(both, "external"), "HDMI-A-1");
        compare(Outputs.matchEntry(["LVDS-1", "DP-3"], "internal"), "LVDS-1");
        compare(Outputs.matchEntry(["DSI-1"], "external"), "");
        verify(Outputs.isInternal("eDP-1"));
        verify(!Outputs.isInternal("HDMI-A-1"));
    }

    function test_priority_is_case_insensitive() {
        compare(Outputs.matchEntry(both, "hdmi-a-1"), "HDMI-A-1");
        compare(Outputs.matchEntry(both, "Internal"), "eDP-1");
    }

    function test_a_single_output_named_as_a_bare_string_still_reads() {
        compare(Outputs.priorityList("HDMI"), ["HDMI"]);
        compare(Outputs.priorityList(""), []);
        compare(Outputs.priorityList(undefined), []);
        compare(Outputs.resolveMainOutput(both, "HDMI", "eDP-1", ""), "HDMI-A-1");
    }

    // ---- fallbacks

    function test_a_list_matching_nothing_falls_through_to_focus() {
        compare(Outputs.matchPriority(both, ["DP-4", "nonsense"]), "");
        compare(Outputs.resolveMainOutput(both, ["DP-4"], "HDMI-A-1", ""), "HDMI-A-1");
    }

    function test_no_list_configured_animates_the_focused_output() {
        compare(Outputs.resolveMainOutput(both, [], "HDMI-A-1", ""), "HDMI-A-1");
        compare(Outputs.resolveMainOutput(both, [], "eDP-1", ""), "eDP-1");
    }

    function test_single_output_animates_whatever_focus_says() {
        compare(Outputs.resolveMainOutput(["winit"], [], "", ""), "winit");
        // A backend reporting an output that isn't connected (or isn't
        // reporting at all) still has to leave something animating.
        compare(Outputs.resolveMainOutput(["winit"], [], "DP-3", ""), "winit");
        compare(Outputs.resolveMainOutput(["winit"], ["HDMI", "internal"], "", ""), "winit");
    }

    function test_no_outputs_resolves_to_nothing() {
        compare(Outputs.resolveMainOutput([], ["HDMI"], "eDP-1", ""), "");
        compare(Outputs.resolveMainOutput([], [], "", "eDP-1"), "");
    }

    // ---- hotplug

    function test_the_main_monitor_takes_the_run_back_when_it_returns() {
        // ["HDMI", "internal"] with the run already on the panel: the list is
        // re-applied on every screen change, so plugging it in wins over the
        // run in flight.
        compare(Outputs.resolveMainOutput(both, ["HDMI", "internal"], "eDP-1", "eDP-1"), "HDMI-A-1");
    }

    function test_unplugging_the_main_monitor_falls_back_down_the_list() {
        compare(Outputs.resolveMainOutput(["eDP-1"], ["HDMI", "internal"], "eDP-1", "HDMI-A-1"), "eDP-1");
        // Nothing left in the list either, so focus takes over.
        compare(Outputs.resolveMainOutput(["DP-1"], ["HDMI", "internal"], "DP-1", "HDMI-A-1"), "DP-1");
    }

    function test_an_unconfigured_run_stays_on_the_screen_it_started_on() {
        // No list, so a monitor arriving must not restart ttfx elsewhere.
        compare(Outputs.resolveMainOutput(both, [], "HDMI-A-1", "eDP-1"), "eDP-1");
        // Unless it was the one that left.
        compare(Outputs.resolveMainOutput(["eDP-1"], [], "eDP-1", "HDMI-A-1"), "eDP-1");
    }

    function test_screen_names_reads_the_name_off_each_screen() {
        compare(Outputs.screenNames([{ name: "eDP-1" }, { name: "HDMI-A-1" }]), ["eDP-1", "HDMI-A-1"]);
        compare(Outputs.screenNames([]), []);
    }
}

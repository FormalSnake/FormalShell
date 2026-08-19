import QtQuick
import QtTest
import "../shell/Screensaver/outputs.js" as Outputs

// Which output the screensaver animates. A nested smoke session has exactly
// one output, so the multi-head rules — follow focus, hold the choice across
// a plug, move it on an unplug — have nowhere else to be proven.
TestCase {
    name: "ScreensaverOutputs"

    function test_focused_output_animates() {
        compare(Outputs.resolveMainOutput(["eDP-1", "HDMI-A-1"], "HDMI-A-1", ""), "HDMI-A-1");
        compare(Outputs.resolveMainOutput(["eDP-1", "HDMI-A-1"], "eDP-1", ""), "eDP-1");
    }

    function test_single_output_animates_whatever_focus_says() {
        compare(Outputs.resolveMainOutput(["winit"], "", ""), "winit");
        // A backend reporting an output that isn't connected (or isn't
        // reporting at all) still has to leave something animating.
        compare(Outputs.resolveMainOutput(["winit"], "DP-3", ""), "winit");
    }

    function test_no_outputs_resolves_to_nothing() {
        compare(Outputs.resolveMainOutput([], "eDP-1", ""), "");
        compare(Outputs.resolveMainOutput([], "", "eDP-1"), "");
    }

    function test_plugging_a_screen_in_leaves_the_run_where_it_is() {
        // Re-resolved on screensChanged with the current answer kept: the
        // animating surface would otherwise restart ttfx from frame 0 on a
        // different screen, mid-effect, because an unrelated monitor arrived.
        compare(Outputs.resolveMainOutput(["eDP-1", "HDMI-A-1"], "HDMI-A-1", "eDP-1"), "eDP-1");
    }

    function test_unplugging_the_animating_screen_moves_the_run() {
        // The dGPU-backed head is the main monitor while it's plugged in; the
        // laptop panel takes over when it isn't.
        compare(Outputs.resolveMainOutput(["eDP-1"], "HDMI-A-1", "HDMI-A-1"), "eDP-1");
        compare(Outputs.resolveMainOutput(["eDP-1"], "eDP-1", "HDMI-A-1"), "eDP-1");
    }

    function test_screen_names_reads_the_name_off_each_screen() {
        compare(Outputs.screenNames([{ name: "eDP-1" }, { name: "HDMI-A-1" }]), ["eDP-1", "HDMI-A-1"]);
        compare(Outputs.screenNames([]), []);
    }
}

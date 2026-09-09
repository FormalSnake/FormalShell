import QtQuick
import QtTest
import qs.Core
import "../shell/Components"
import "../shell/Theme/icons.js" as Icons

// Icon's content rule (M53 D3): nineteen consumers bind `name` to a ternary,
// so a glyph swap is a state change on a cell already on screen and crosses
// on `fast` rather than cutting. The two slots trade places on each change;
// the second one is not built into the frame until the first one, so an icon
// that never swaps costs one node.
//
// The glyphs are read back through the same icons.js the component resolves
// them with, since a raw codepoint in a test file is exactly the rewrite
// hazard the component exists to keep out of surface files.
TestCase {
    id: testCase
    name: "IconCrossfade"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component {
        id: iconComponent
        Icon {}
    }

    property bool _originalMotionEnabled

    function init() {
        testCase._originalMotionEnabled = Theme.motionEnabled;
    }

    function cleanup() {
        Theme.motionEnabled = testCase._originalMotionEnabled;
    }

    function make(props) {
        var icon = createTemporaryObject(iconComponent, testCase, props);
        verify(icon);
        waitForRendering(icon);
        return icon;
    }

    // The two glyph slots, in declaration order. They carry no ids reachable
    // from here, so they are picked out by being the icon's only Text
    // children.
    function slots(icon) {
        var out = [];
        for (var i = 0; i < icon.children.length; i++) {
            if (icon.children[i].text !== undefined)
                out.push(icon.children[i]);
        }
        return out;
    }

    function test_a_resting_icon_draws_one_glyph_in_one_slot() {
        var icon = make({ name: "wifi" });
        var pair = slots(icon);
        compare(pair.length, 2);
        compare(pair[0].text, Icons.glyph(Theme.iconSet, "wifi"));
        compare(pair[0].opacity, 1);
        verify(!pair[1].visible);
        // The public geometry is a Text's: a `size`-wide box as tall as the
        // glyph's own line.
        compare(icon.width, icon.size);
        verify(icon.implicitHeight > 0);
    }

    function test_a_name_change_fades_the_old_slot_out_and_the_new_one_in() {
        var icon = make({ name: "wifi" });
        var pair = slots(icon);
        verify(Icons.glyph(Theme.iconSet, "wifi") !== Icons.glyph(Theme.iconSet, "bell"));

        icon.name = "bell";
        // The incoming glyph lands in the idle slot on the same tick, and
        // the outgoing one is still up: this is a crossfade, not a swap
        // followed by a fade.
        compare(pair[1].text, Icons.glyph(Theme.iconSet, "bell"));
        verify(pair[1].visible);
        compare(pair[0].text, Icons.glyph(Theme.iconSet, "wifi"));
        verify(pair[0].opacity > 0);

        tryCompare(pair[1], "opacity", 1, 1000);
        tryCompare(pair[0], "opacity", 0, 1000);
    }

    // The slots keep trading rather than the new glyph always landing in the
    // second one, so a cell whose ternary flips back and forth never pays a
    // third node.
    function test_a_second_change_goes_back_to_the_first_slot() {
        var icon = make({ name: "wifi" });
        var pair = slots(icon);
        icon.name = "bell";
        tryCompare(pair[1], "opacity", 1, 1000);

        icon.name = "clock";
        compare(pair[0].text, Icons.glyph(Theme.iconSet, "clock"));
        tryCompare(pair[0], "opacity", 1, 1000);
        tryCompare(pair[1], "opacity", 0, 1000);
    }

    // Every name missing from the set resolves to the same fallback, and a
    // crossfade between a glyph and itself is a frame of nothing happening.
    function test_a_change_that_resolves_to_the_same_glyph_arms_nothing() {
        var icon = make({ name: "not-an-icon-name" });
        var pair = slots(icon);
        icon.name = "also-not-an-icon-name";
        compare(pair[0].text, Icons.glyph(Theme.iconSet, "circle-help"));
        verify(!pair[1].visible);
        compare(pair[0].opacity, 1);
    }

    // motion.enabled=false zeroes `fast`, and a zero-duration Behavior lands
    // on the same tick it starts, so the swap is a cut with no frame in
    // which both glyphs are up.
    function test_motion_disabled_swaps_on_the_same_tick() {
        Theme.motionEnabled = false;
        var icon = make({ name: "wifi" });
        var pair = slots(icon);
        icon.name = "bell";
        compare(pair[1].text, Icons.glyph(Theme.iconSet, "bell"));
        compare(pair[1].opacity, 1);
        compare(pair[0].opacity, 0);
    }
}

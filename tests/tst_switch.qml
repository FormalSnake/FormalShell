import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Switch's contract (DESIGN.md §2, M44 D4): a `controlHeight` square control
// holding a `controlHeight` x `huge` track
// at full radius, `muted` off and `primary` on, a `background` knob that
// slides between the two ends, the ring on `cursor`, and `toggled` carrying
// the value the owner should write.
//
// Asserted against a sentinel palette rather than Palette.fallback(): the
// zinc fallback shares hex values between roles, so a track that had gone
// back to `accent` would still satisfy a comparison made against the real
// set.
TestCase {
    id: testCase
    name: "Switch"
    width: 400
    height: 200
    visible: true
    when: windowShown

    readonly property var sentinelColors: ({
        background: "#010101",
        foreground: "#eeeeee",
        mutedForeground: "#aaaaaa",
        card: "#151515",
        border: "#444444",
        muted: "#2a2a2a",
        accent: "#3b3b3b",
        accentForeground: "#dddddd",
        primary: "#1133ff",
        primaryForeground: "#ffdd00",
        destructive: "#ff2222",
        destructiveForeground: "#22ff88",
        warning: "#ffaa00",
        warningForeground: "#001122",
        ring: "#00ccff"
    })

    property var _originalColor

    function init() {
        testCase._originalColor = Theme.color;
        Theme.color = testCase.sentinelColors;
    }

    function cleanup() {
        Theme.color = testCase._originalColor;
    }

    Component {
        id: switchComponent
        Switch {}
    }

    Component {
        id: spyComponent
        SignalSpy {}
    }

    function make(props) {
        var control = createTemporaryObject(switchComponent, testCase, props);
        verify(control);
        waitForRendering(control);
        wait(200);
        return control;
    }

    // Declaration order: ring halo, track, knob.
    function layers(control) {
        var out = [];
        for (var i = 0; i < control.children.length; i++) {
            var child = control.children[i];
            if (child.radius !== undefined)
                out.push(child);
        }
        return out;
    }

    function haloOf(control) { return layers(control)[0]; }
    function trackOf(control) { return layers(control)[1]; }
    function knobOf(control) { return layers(control)[2]; }

    function test_it_paints_three_layers() {
        compare(layers(make({})).length, 3);
    }

    function test_the_track_is_thirty_two_by_eighteen_in_tokens() {
        var control = make({});
        compare(control.implicitWidth, Theme.space.controlHeight);
        compare(control.implicitHeight, Theme.space.controlHeight);
        compare(trackOf(control).height, Theme.space.huge);
    }

    function test_the_track_radius_is_full() {
        var track = trackOf(make({}));
        compare(track.radius, track.height / 2);
    }

    function test_off_is_muted_and_on_is_primary() {
        verify(Qt.colorEqual(trackOf(make({ checked: false })).color, Theme.color.muted));
        verify(Qt.colorEqual(trackOf(make({ checked: true })).color, Theme.color.primary));
    }

    // The knob slides on a Behavior already; the track colour crossfades
    // beside it (M51 Task 5), so a toggle never has one half of the switch
    // move and the other half pop.
    function test_the_track_crossfades_when_checked_changes() {
        var control = make({ checked: false });
        control.checked = true;
        tryCompare(trackOf(control), "color", Theme.color.primary, 1000);
    }

    function test_the_knob_is_a_background_circle() {
        var knob = knobOf(make({}));
        verify(Qt.colorEqual(knob.color, Theme.color.background));
        compare(knob.width, knob.height);
        compare(knob.radius, knob.height / 2);
    }

    function test_the_knob_slides_to_the_far_end_when_checked() {
        var off = make({ checked: false });
        var on = make({ checked: true });
        var offKnob = knobOf(off);
        var onKnob = knobOf(on);
        verify(onKnob.x > offKnob.x);
        // Symmetric: the same inset from either end of the track.
        compare(offKnob.x, on.width - onKnob.x - onKnob.width);
    }

    // The slide is a Behavior, so the knob reaches the far end a frame or
    // more after `checked` changes rather than on the same tick.
    function test_the_knob_animates_to_the_far_end_when_checked_changes() {
        var control = make({ checked: false });
        var knob = knobOf(control);
        control.checked = true;
        tryCompare(knob, "x", control.width - knob.width - Theme.borderWidth * 2, 1000);
    }

    function test_cursor_draws_the_ring() {
        var control = make({ cursor: true });
        var halo = haloOf(control);
        verify(halo.visible);
        verify(Qt.colorEqual(halo.color, Theme.color.ring));
        compare(halo.opacity, Theme.ringAlpha);
        compare(trackOf(control).border.width, Theme.borderWidth);
        verify(Qt.colorEqual(trackOf(control).border.color, Theme.color.ring));
    }

    function test_no_cursor_draws_no_ring_and_no_border() {
        var control = make({});
        verify(!haloOf(control).visible);
        compare(trackOf(control).border.width, 0);
    }

    // Controlled: the owner writes `checked`, so a press must not flip it
    // here or the owner's binding is gone after the first click.
    function test_a_click_reports_the_new_value_without_writing_it() {
        var control = make({ checked: false });
        var spy = createTemporaryObject(spyComponent, testCase, { target: control, signalName: "toggled" });
        verify(spy);
        mouseClick(control, control.width / 2, control.height / 2);
        compare(spy.count, 1);
        compare(spy.signalArguments[0][0], true);
        compare(control.checked, false);
    }

    function test_toggle_is_the_keyboard_entry_point() {
        var control = make({ checked: true });
        var spy = createTemporaryObject(spyComponent, testCase, { target: control, signalName: "toggled" });
        verify(spy);
        control.toggle();
        compare(spy.count, 1);
        compare(spy.signalArguments[0][0], false);
    }
}

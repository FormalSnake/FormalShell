import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Input's contract (DESIGN.md §2): an `input` border at `radiusMd`,
// `controlHeight` tall, the ring while it holds focus, a `destructive`
// border plus a caption while `error`. M51 Task 5: the border colour and
// the ring's own opacity both transition on the effects family for focus,
// blur and error, rather than popping.
//
// Asserted against a sentinel palette rather than Palette.fallback(): the
// zinc fallback shares hex values between roles, so a border that had gone
// back to `input` would still satisfy a comparison made against the real
// fallback set.
TestCase {
    id: testCase
    name: "Input"
    width: 400
    height: 200
    visible: true
    when: windowShown

    // The alpha the table's `cursor` ring layer carries, written out rather
    // than read back off the table: an assertion sourced from the same place
    // as the value under test agrees with itself whatever the table says.
    readonly property real ringAlpha: 0.5

    readonly property var sentinelColors: ({
        background: "#010101",
        foreground: "#eeeeee",
        mutedForeground: "#aaaaaa",
        card: "#151515",
        border: "#444444",
        input: "#556677",
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
        id: inputComponent
        Input { width: 200 }
    }

    function make(props) {
        var control = createTemporaryObject(inputComponent, testCase, props);
        verify(control);
        waitForRendering(control);
        wait(200);
        return control;
    }

    // Declaration order: the ring halo, the frame, the error caption. The
    // frame is a `Box`, so its border is on the rectangle Box draws (the
    // second from the end of its own, tst_box.qml walks the same shape) and
    // the field itself sits in the box's content slot.
    function ringOf(control) { return control.children[0]; }
    function frameOf(control) { return control.children[1]; }
    function errorLabelOf(control) { return control.children[2]; }

    function bodyOf(box) {
        var out = [];
        for (var i = 0; i < box.children.length; i++) {
            if (box.children[i].radius !== undefined && box.children[i].border !== undefined)
                out.push(box.children[i]);
        }
        return out[out.length - 2];
    }

    function frameBodyOf(control) { return bodyOf(frameOf(control)); }
    function textInputOf(control) { return frameOf(control).contentItem.children[1]; }

    // The frame is one `Box` on the `input` role (M60 T1b), so the sunken
    // lines that role's entry declares are drawn rather than dropped.
    function test_the_frame_is_a_box_on_the_input_role() {
        var control = make({});
        compare(frameOf(control).role, "input");
        verify(frameOf(control).contentItem);
        verify(Qt.colorEqual(frameBodyOf(control).color, Theme.box("input").fill));
    }

    function test_at_rest_the_border_is_input_and_the_ring_is_hidden() {
        var control = make({});
        verify(Qt.colorEqual(frameBodyOf(control).border.color, Theme.color.input));
        compare(ringOf(control).opacity, 0);
        verify(!ringOf(control).visible);
    }

    function test_focus_swaps_the_border_to_ring_and_shows_the_halo() {
        var control = make({});
        textInputOf(control).forceActiveFocus();
        tryCompare(frameBodyOf(control).border, "color", Theme.color.ring, 1000);
        // The halo is the table's own ring layer, filled at that layer's
        // alpha, so what fades is its presence and not its colour.
        tryCompare(ringOf(control), "opacity", 1, 1000);
        verify(Qt.colorEqual(ringOf(control).color, Qt.alpha(Theme.color.ring, testCase.ringAlpha)));
        verify(ringOf(control).visible);
    }

    function test_blur_returns_the_border_to_input_and_hides_the_halo() {
        var control = make({});
        var input = textInputOf(control);
        input.forceActiveFocus();
        tryCompare(frameBodyOf(control).border, "color", Theme.color.ring, 1000);
        input.focus = false;
        tryCompare(frameBodyOf(control).border, "color", Theme.color.input, 1000);
        tryCompare(ringOf(control), "opacity", 0, 1000);
    }

    // A validation error still has to read as landing instantly, so it
    // takes no special-cased skip past the colour Behavior everything else
    // uses, it just rides a clock short enough to satisfy that.
    function test_error_reaches_destructive_on_the_colour_clock() {
        var control = make({ error: true });
        tryCompare(frameBodyOf(control).border, "color", Theme.color.destructive, Theme.motion.effectsSlow + 500);
    }

    function test_error_wins_over_focus() {
        var control = make({ error: true });
        textInputOf(control).forceActiveFocus();
        tryCompare(frameBodyOf(control).border, "color", Theme.color.destructive, 1000);
    }

    function test_error_caption_shows_only_with_error_text() {
        var bare = make({ error: true, errorText: "" });
        verify(!errorLabelOf(bare).visible);
        var withText = make({ error: true, errorText: "Required" });
        verify(errorLabelOf(withText).visible);
        compare(errorLabelOf(withText).text, "Required");
    }
}

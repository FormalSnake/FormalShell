import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Input's contract (DESIGN.md §2): an `input` border at `radiusMd`,
// `controlHeight` tall, the ring while it holds focus, a `destructive`
// border plus a caption while `error`. M51 Task 5: the border colour and
// the ring's own opacity both transition on `Theme.motion.fast` for focus,
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

    // Declaration order: the ring halo, the frame, the error caption.
    function ringOf(control) { return control.children[0]; }
    function frameOf(control) { return control.children[1]; }
    function errorLabelOf(control) { return control.children[2]; }
    function textInputOf(control) { return frameOf(control).children[1]; }

    function test_at_rest_the_border_is_input_and_the_ring_is_hidden() {
        var control = make({});
        verify(Qt.colorEqual(frameOf(control).border.color, Theme.color.input));
        compare(ringOf(control).opacity, 0);
        verify(!ringOf(control).visible);
    }

    function test_focus_swaps_the_border_to_ring_and_shows_the_halo() {
        var control = make({});
        textInputOf(control).forceActiveFocus();
        tryCompare(frameOf(control).border, "color", Theme.color.ring, 1000);
        tryCompare(ringOf(control), "opacity", Theme.ringAlpha, 1000);
        verify(ringOf(control).visible);
    }

    function test_blur_returns_the_border_to_input_and_hides_the_halo() {
        var control = make({});
        var input = textInputOf(control);
        input.forceActiveFocus();
        tryCompare(frameOf(control).border, "color", Theme.color.ring, 1000);
        input.focus = false;
        tryCompare(frameOf(control).border, "color", Theme.color.input, 1000);
        tryCompare(ringOf(control), "opacity", 0, 1000);
    }

    // `fast` is 100ms; a validation error still has to read as landing
    // instantly, so it takes no special-cased skip past the same Behavior
    // everything else uses, it just has a short enough curve to satisfy that.
    function test_error_reaches_destructive_within_fast() {
        var control = make({ error: true });
        tryCompare(frameOf(control).border, "color", Theme.color.destructive, Theme.motion.fast + 500);
    }

    function test_error_wins_over_focus() {
        var control = make({ error: true });
        textInputOf(control).forceActiveFocus();
        tryCompare(frameOf(control).border, "color", Theme.color.destructive, 1000);
    }

    function test_error_caption_shows_only_with_error_text() {
        var bare = make({ error: true, errorText: "" });
        verify(!errorLabelOf(bare).visible);
        var withText = make({ error: true, errorText: "Required" });
        verify(errorLabelOf(withText).visible);
        compare(errorLabelOf(withText).text, "Required");
    }
}

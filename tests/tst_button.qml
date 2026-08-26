import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Button's four variants (DESIGN.md §2): which fill, which border, which
// ink, plus the ring, the hover treatment and the disabled dim. IconButton
// is the same component as a square ghost, so it rides along here.
//
// Verified against a synthetic palette, not Palette.fallback()'s real hex
// values: the zinc fallback shares a hex between roles, which would make a
// hex-equality assertion unable to tell a correct role from a swapped one.
TestCase {
    id: testCase
    name: "Button"
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
        accent: "#2a2a2a",
        accentForeground: "#dddddd",
        primary: "#1133ff",
        primaryForeground: "#ffdd00",
        destructive: "#ff2222",
        destructiveForeground: "#22ff88",
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
        id: buttonComponent
        Button {}
    }

    Component {
        id: iconButtonComponent
        IconButton {}
    }

    function settle(item) {
        waitForRendering(item);
        wait(50);
    }

    // The painted layers, in declaration order: ring halo, body, pointer
    // wash. test_button_paints_three_layers is what fails if that order
    // changes under the tests below.
    function layers(button) {
        var out = [];
        for (var i = 0; i < button.children.length; i++) {
            var child = button.children[i];
            if (child.radius !== undefined && child.border !== undefined)
                out.push(child);
        }
        return out;
    }

    function findText(item, wanted) {
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i];
            if (child.font !== undefined && child.text === wanted)
                return child;
            var nested = findText(child, wanted);
            if (nested)
                return nested;
        }
        return null;
    }

    function make(component, props) {
        var button = createTemporaryObject(component, testCase, props);
        verify(button);
        settle(button);
        return button;
    }

    function test_button_paints_three_layers() {
        var button = make(buttonComponent, { text: "OK" });
        compare(layers(button).length, 3);
    }

    function test_geometry_tokens() {
        var button = make(buttonComponent, { text: "Speed test" });
        compare(button.implicitHeight, Theme.space.controlHeight);
        compare(layers(button)[1].radius, Theme.radiusMd);
        // The label plus a control gutter either side.
        var label = findText(button, "Speed test");
        verify(label);
        compare(button.implicitWidth, label.implicitWidth + Theme.space.controlPaddingX * 2);
    }

    function test_default_fills_with_primary() {
        var button = make(buttonComponent, { text: "Connect" });
        var body = layers(button)[1];
        verify(Qt.colorEqual(body.color, Theme.color.primary));
        compare(body.border.width, 0);
        verify(Qt.colorEqual(findText(button, "Connect").color, Theme.color.primaryForeground));
    }

    function test_destructive_fills_with_destructive() {
        var button = make(buttonComponent, { variant: "destructive", text: "Forget" });
        var body = layers(button)[1];
        verify(Qt.colorEqual(body.color, Theme.color.destructive));
        compare(body.border.width, 0);
        verify(Qt.colorEqual(findText(button, "Forget").color, Theme.color.destructiveForeground));
    }

    function test_outline_is_transparent_behind_a_border() {
        var button = make(buttonComponent, { variant: "outline", text: "Speed test" });
        var body = layers(button)[1];
        compare(body.color.a, 0);
        compare(body.border.width, Theme.borderWidth);
        verify(Qt.colorEqual(body.border.color, Theme.color.border));
        verify(Qt.colorEqual(findText(button, "Speed test").color, Theme.color.foreground));
    }

    function test_ghost_draws_no_chrome_at_rest() {
        var button = make(buttonComponent, { variant: "ghost", text: "Clear" });
        var body = layers(button)[1];
        compare(body.color.a, 0);
        compare(body.border.width, 0);
        verify(Qt.colorEqual(findText(button, "Clear").color, Theme.color.foreground));
    }

    function test_cursor_draws_the_ring_on_any_variant() {
        var filled = make(buttonComponent, { text: "Connect", cursor: true });
        var halo = layers(filled)[0];
        verify(halo.visible);
        verify(Qt.colorEqual(halo.color, Theme.color.ring));
        compare(halo.opacity, Theme.ringAlpha);
        // A filled variant has no border of its own, so the ring is the only
        // thing that gives it one.
        compare(layers(filled)[1].border.width, Theme.borderWidth);
        verify(Qt.colorEqual(layers(filled)[1].border.color, Theme.color.ring));

        var ghost = make(buttonComponent, { variant: "ghost", text: "Clear" });
        verify(!layers(ghost)[0].visible);
    }

    // A variant carrying its own colour blends toward `background` and stays
    // opaque; every other one takes the wash. The old treatment dropped the
    // body's opacity, which on a panel drawn at `surfaceOpacity` showed the
    // wallpaper through the button.
    function test_hover_blends_a_colour_and_washes_everything_else() {
        var filled = make(buttonComponent, { text: "Connect", hovered: true });
        var body = layers(filled)[1];
        compare(body.opacity, 1);
        tryCompare(body, "color", Theme.hoverFilled(Theme.color.primary));
        verify(!Qt.colorEqual(body.color, Theme.color.primary));
        compare(body.color.a, 1);
        compare(layers(filled)[2].opacity, 0);

        var ghost = make(buttonComponent, { variant: "ghost", text: "Clear", hovered: true });
        verify(Qt.colorEqual(layers(ghost)[2].color, Theme.hoverFill));
        tryCompare(layers(ghost)[2], "opacity", 1);
        compare(layers(ghost)[1].opacity, 1);
    }

    // The chosen option in a `ButtonGroup`: its fill is `background`, so it
    // takes the wash rather than a blend, and keeps reading as chosen under
    // the pointer.
    function test_selected_takes_the_wash_over_its_own_fill() {
        var chosen = make(buttonComponent, { variant: "selected", text: "Balanced", hovered: true });
        verify(Qt.colorEqual(layers(chosen)[1].color, Theme.color.background));
        verify(Qt.colorEqual(layers(chosen)[2].color, Theme.hoverFill));
        tryCompare(layers(chosen)[2], "opacity", 1);
    }

    // Press is the same wash one step on, never `accent` painted over a
    // primary fill.
    function test_press_deepens_the_treatment_the_variant_already_takes() {
        var ghost = make(buttonComponent, { variant: "ghost", text: "Clear" });
        mousePress(ghost, ghost.width / 2, ghost.height / 2);
        verify(Qt.colorEqual(layers(ghost)[2].color, Theme.pressFill));
        mouseRelease(ghost, ghost.width / 2, ghost.height / 2);

        var filled = make(buttonComponent, { text: "Connect" });
        mousePress(filled, filled.width / 2, filled.height / 2);
        tryCompare(layers(filled)[1], "color", Theme.pressFilled(Theme.color.primary));
        compare(layers(filled)[2].opacity, 0);
        mouseRelease(filled, filled.width / 2, filled.height / 2);
    }

    // Sans, because a button label is words (DESIGN.md §1 "Type").
    function test_the_label_face_is_sans() {
        var button = make(buttonComponent, { text: "Speed test" });
        compare(findText(button, "Speed test").font.family, Theme.fontFamilySans);
    }

    function test_disabled_dims_the_whole_button() {
        var button = make(buttonComponent, { text: "Connect", enabled: false });
        compare(button.opacity, 0.5);
    }

    function test_an_icon_leads_the_label() {
        var bare = make(buttonComponent, { text: "Connect" });
        var withIcon = make(buttonComponent, { text: "Connect", icon: "wifi" });
        verify(withIcon.implicitWidth > bare.implicitWidth);
    }

    function test_icon_button_is_a_square_ghost() {
        var button = make(iconButtonComponent, { name: "x" });
        compare(button.variant, "ghost");
        compare(button.implicitWidth, Theme.space.controlHeight);
        compare(button.implicitHeight, Theme.space.controlHeight);
        compare(layers(button)[1].border.width, 0);
    }

    function test_click_fires_once() {
        var button = make(buttonComponent, { text: "OK" });
        var spy = createTemporaryObject(spyComponent, testCase, { target: button, signalName: "clicked" });
        verify(spy);
        mouseClick(button, button.width / 2, button.height / 2);
        compare(spy.count, 1);
    }

    Component {
        id: spyComponent
        SignalSpy {}
    }
}

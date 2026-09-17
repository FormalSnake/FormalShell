import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Button's four variants (DESIGN.md §2): which fill, which border, which
// ink, plus the ring, the hover treatment and the disabled dim. IconButton
// is the same component as a square ghost, so it rides along here.
//
// The button is a `Box`, so its rectangles are the ones Box draws in that
// order (tst_box.qml walks the same shape): the cursor's halo when there is
// one, then the fill, then the pointer's wash. The halo exists only while
// the cursor is on it, so the three are found by shape rather than by a
// fixed index.
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

    function rects(button) {
        var out = [];
        for (var i = 0; i < button.children.length; i++) {
            var child = button.children[i];
            if (child.radius !== undefined && child.border !== undefined)
                out.push(child);
        }
        return out;
    }

    // The fill and the wash are always drawn, in that order and last, so the
    // halo is whatever is in front of them; test_a_resting_button_is_a_fill
    // _and_its_wash is what fails if that stops being true.
    function body(button) {
        var all = rects(button);
        return all[all.length - 2];
    }

    function wash(button) {
        var all = rects(button);
        return all[all.length - 1];
    }

    function halo(button) {
        var all = rects(button);
        return all.length > 2 ? all[0] : null;
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

    function test_a_resting_button_is_a_fill_and_its_wash() {
        var button = make(buttonComponent, { text: "OK" });
        compare(rects(button).length, 2);
        compare(halo(button), null);
        // The cursor's halo is a third rectangle, and only then.
        var ringed = make(buttonComponent, { text: "OK", cursor: true });
        compare(rects(ringed).length, 3);
        verify(halo(ringed));
    }

    function test_geometry_tokens() {
        var button = make(buttonComponent, { text: "Speed test" });
        compare(button.implicitHeight, Theme.space.controlHeight);
        compare(body(button).radius, Theme.radiusMd);
        // The label plus a control gutter either side.
        var label = findText(button, "Speed test");
        verify(label);
        compare(button.implicitWidth, label.implicitWidth + Theme.space.controlPaddingX * 2);
    }

    function test_default_fills_with_primary() {
        var button = make(buttonComponent, { text: "Connect" });
        verify(Qt.colorEqual(body(button).color, Theme.color.primary));
        compare(body(button).border.width, 0);
        verify(Qt.colorEqual(findText(button, "Connect").color, Theme.color.primaryForeground));
    }

    function test_destructive_fills_with_destructive() {
        var button = make(buttonComponent, { variant: "destructive", text: "Forget" });
        verify(Qt.colorEqual(body(button).color, Theme.color.destructive));
        compare(body(button).border.width, 0);
        verify(Qt.colorEqual(findText(button, "Forget").color, Theme.color.destructiveForeground));
    }

    function test_outline_is_transparent_behind_a_border() {
        var button = make(buttonComponent, { variant: "outline", text: "Speed test" });
        compare(body(button).color.a, 0);
        compare(body(button).border.width, Theme.borderWidth);
        verify(Qt.colorEqual(body(button).border.color, Theme.color.border));
        verify(Qt.colorEqual(findText(button, "Speed test").color, Theme.color.foreground));
    }

    function test_ghost_draws_no_chrome_at_rest() {
        var button = make(buttonComponent, { variant: "ghost", text: "Clear" });
        compare(body(button).color.a, 0);
        compare(body(button).border.width, 0);
        verify(Qt.colorEqual(findText(button, "Clear").color, Theme.color.foreground));
    }

    function test_cursor_draws_the_ring_on_any_variant() {
        var filled = make(buttonComponent, { text: "Connect", cursor: true });
        var ring = halo(filled);
        verify(ring.visible);
        // The table's own ring layer: filled at its alpha rather than opaque
        // under a 0.5 opacity, which is the same band of pixels.
        verify(Qt.colorEqual(ring.color, Qt.alpha(Theme.color.ring, testCase.ringAlpha)));
        compare(ring.opacity, 1);
        // A filled variant has no border of its own, so the ring is the only
        // thing that gives it one.
        compare(body(filled).border.width, Theme.borderWidth);
        verify(Qt.colorEqual(body(filled).border.color, Theme.color.ring));

        var ghost = make(buttonComponent, { variant: "ghost", text: "Clear" });
        compare(halo(ghost), null);
    }

    // A variant carrying its own colour blends toward `background` and stays
    // opaque; every other one takes the wash. The old treatment dropped the
    // body's opacity, which on a panel drawn at `surfaceOpacity` showed the
    // wallpaper through the button.
    function test_hover_blends_a_colour_and_washes_everything_else() {
        var filled = make(buttonComponent, { text: "Connect", hovered: true });
        compare(body(filled).opacity, 1);
        tryCompare(body(filled), "color", Theme.hoverFilled(Theme.color.primary));
        verify(!Qt.colorEqual(body(filled).color, Theme.color.primary));
        compare(body(filled).color.a, 1);
        compare(wash(filled).opacity, 0);

        var ghost = make(buttonComponent, { variant: "ghost", text: "Clear", hovered: true });
        verify(Qt.colorEqual(wash(ghost).color, Theme.hoverFill));
        tryCompare(wash(ghost), "opacity", 1);
        compare(body(ghost).opacity, 1);
    }

    // The chosen option in a `ButtonGroup`: its fill is `background`, so it
    // takes the wash rather than a blend, and keeps reading as chosen under
    // the pointer.
    function test_selected_takes_the_wash_over_its_own_fill() {
        var chosen = make(buttonComponent, { variant: "selected", text: "Balanced", hovered: true });
        verify(Qt.colorEqual(body(chosen).color, Theme.color.background));
        verify(Qt.colorEqual(wash(chosen).color, Theme.hoverFill));
        tryCompare(wash(chosen), "opacity", 1);
    }

    // Press is the same wash one step on, never `accent` painted over a
    // primary fill.
    function test_press_deepens_the_treatment_the_variant_already_takes() {
        var ghost = make(buttonComponent, { variant: "ghost", text: "Clear" });
        mousePress(ghost, ghost.width / 2, ghost.height / 2);
        verify(Qt.colorEqual(wash(ghost).color, Theme.pressFill));
        mouseRelease(ghost, ghost.width / 2, ghost.height / 2);

        var filled = make(buttonComponent, { text: "Connect" });
        mousePress(filled, filled.width / 2, filled.height / 2);
        tryCompare(body(filled), "color", Theme.pressFilled(Theme.color.primary));
        compare(wash(filled).opacity, 0);
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
        compare(body(button).border.width, 0);
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

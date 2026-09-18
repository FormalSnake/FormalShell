import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Box's contract (M59 T4): it draws the box a table entry describes and
// nothing else, so each kind of layer is asserted once here. A box with no
// layers and no face has to stay one Rectangle and its border, which is the
// cost every surface in the shell pays today.
//
// Asserted against a sentinel palette rather than Palette.fallback(), the
// same reason tst_switch.qml gives: the zinc fallback shares hex values
// between roles, so a fill that had gone back to the wrong role would still
// satisfy a comparison made against the real set.
//
// The layer kinds no table carries yet (a hairline, a face, a cast) are
// driven through `box` directly, with a resolved description written out:
// that property is what a surface holding its own box assigns, and it is
// the only way to draw a shape metamorphosis does not ask for.
TestCase {
    id: testCase
    name: "Box"
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
        cardForeground: "#f0f0f0",
        popover: "#181818",
        popoverForeground: "#f1f1f1",
        muted: "#2a2a2a",
        accent: "#3b3b3b",
        accentForeground: "#dddddd",
        primary: "#1133ff",
        primaryForeground: "#ffdd00",
        destructive: "#ff2222",
        destructiveForeground: "#22ff88",
        warning: "#ffaa00",
        warningForeground: "#001122",
        border: "#444444",
        input: "#333344",
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
        id: boxComponent
        Box {
            width: 100
            height: 40
        }
    }

    function make(props) {
        var box = createTemporaryObject(boxComponent, testCase, props);
        verify(box);
        waitForRendering(box);
        wait(200);
        return box;
    }

    // Rectangles among the box's own children, in declaration order: the
    // rings, the fill, and the pointer's wash. A face and the hairlines
    // live one level down, so they are read off their own container.
    function rects(box) {
        var out = [];
        for (var i = 0; i < box.children.length; i++) {
            var child = box.children[i];
            if (child.radius !== undefined)
                out.push(child);
        }
        return out;
    }

    function visibleRects(box) {
        var all = rects(box);
        var out = [];
        for (var i = 0; i < all.length; i++) {
            if (all[i].visible)
                out.push(all[i]);
        }
        return out;
    }

    function effects(box) {
        var out = [];
        for (var i = 0; i < box.children.length; i++) {
            if (box.children[i].shadowEnabled !== undefined)
                out.push(box.children[i]);
        }
        return out;
    }

    // The two containers read by their own shape rather than by their index
    // among the children, since the box appends its content slot after them:
    // the hairlines live in the one clipped item, the face in the one Loader.
    function hairlineBox(box) {
        for (var i = 0; i < box.children.length; i++) {
            if (box.children[i].clip === true)
                return box.children[i];
        }
        return null;
    }

    function faceLoader(box) {
        for (var i = 0; i < box.children.length; i++) {
            if (box.children[i].sourceComponent !== undefined)
                return box.children[i];
        }
        return null;
    }

    // A container's own rectangles, for the face and the hairlines.
    function childRects(item) {
        var out = [];
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i];
            if (child.radius !== undefined)
                out.push(child);
        }
        return out;
    }

    function resolved(extra) {
        var box = {
            fill: "transparent", radius: 8, border: null, face: null,
            wash: null, edge: null, hairlines: [], rings: [], insetRings: [], casts: []
        };
        for (var key in extra)
            box[key] = extra[key];
        return box;
    }

    // --- The plain case --------------------------------------------------

    function test_a_fill_and_a_border_are_one_rectangle() {
        var box = make({ role: "card" });
        var drawn = visibleRects(box);
        compare(drawn.length, 1);
        verify(Qt.colorEqual(drawn[0].color, Qt.alpha(Theme.color.card, Theme.surfaceOpacity)));
        verify(Qt.colorEqual(drawn[0].border.color, Theme.color.border));
        compare(drawn[0].border.width, Theme.borderWidth);
        compare(drawn[0].radius, Theme.radiusXl);
        compare(effects(box).length, 0);
    }

    function test_a_role_with_no_border_draws_none() {
        var drawn = visibleRects(make({ role: "trough" }));
        compare(drawn.length, 1);
        verify(Qt.colorEqual(drawn[0].color, Theme.color.muted));
        compare(drawn[0].border.width, 0);
        compare(drawn[0].radius, Theme.radiusMd);
    }

    // A state the table describes with one key keeps the resting box under
    // it, and the states are the table's, not the primitive's.
    function test_a_state_changes_the_fill() {
        verify(Qt.colorEqual(visibleRects(make({ role: "cell", state: "active" }))[0].color,
            Theme.color.primary));
        verify(Qt.colorEqual(visibleRects(make({ role: "cell", state: "selected" }))[0].color,
            Theme.color.accent));
        var ghost = visibleRects(make({ role: "cell", state: "ghost" }))[0];
        verify(Qt.colorEqual(ghost.color, "transparent"));
        compare(ghost.border.width, 0);
        verify(Qt.colorEqual(visibleRects(make({ role: "cell", state: "destructive" }))[0].border.color,
            Theme.color.destructive));
    }

    // The same crossfade Cell and Button carried before this file existed:
    // a state change on a box already on screen arrives as a colour
    // travelling rather than cutting.
    function test_the_fill_crossfades_on_a_state_change() {
        var box = make({ role: "cell", state: "rest" });
        var body = visibleRects(box)[0];
        box.state = "active";
        tryCompare(body, "color", Theme.color.primary, 1000);
    }

    // A literal colour rather than a palette role, through the same
    // resolution: the modal scrim is the one box that names one.
    function test_a_literal_colour_resolves_under_its_own_alpha() {
        var drawn = visibleRects(make({ role: "scrim" }));
        compare(drawn.length, 1);
        verify(Qt.colorEqual(drawn[0].color, Qt.rgba(0, 0, 0, 0.5)));
        compare(drawn[0].radius, 0);
        compare(drawn[0].border.width, 0);
    }

    // --- The radius ------------------------------------------------------

    function test_the_consumer_can_override_the_radius() {
        compare(visibleRects(make({ role: "card", radius: 3 }))[0].radius, 3);
    }

    // `pill` is the one step that needs the item's own extent, so it is
    // resolved here rather than in the table.
    function test_pill_resolves_against_the_box_itself() {
        var box = make({ role: "switch.knob" });
        compare(visibleRects(box)[0].radius, Theme.pillRadius(Math.min(box.width, box.height)));
    }

    // --- The layers ------------------------------------------------------

    // The keyboard cursor's halo: a filled rounded rectangle at a negative
    // margin of its own spread, drawn before the fill and so under it, which
    // is what CSS paints for a spread with no blur. Filled and not stroked,
    // because the fill over it is translucent and a stroked band would show
    // the desktop between itself and the border.
    function test_a_ring_layer_draws_a_band_outside_the_box() {
        var box = make({ role: "cursor", radius: 8 });
        var drawn = visibleRects(box);
        compare(drawn.length, 2);
        var ring = drawn[0];
        compare(ring.anchors.margins, -Theme.ringWidth);
        compare(ring.width, box.width + Theme.ringWidth * 2);
        compare(ring.radius, 8 + Theme.ringWidth);
        verify(Qt.colorEqual(ring.color, Qt.alpha(Theme.color.ring, testCase.ringAlpha)));
        verify(Qt.colorEqual(drawn[1].border.color, Theme.color.ring));
    }

    function test_a_hairline_draws_one_line_along_its_own_edge() {
        var box = make({ box: resolved({
            fill: "#151515",
            border: { color: "#444444", width: 1 },
            hairlines: [{ edge: "right", thickness: 1, inset: true, color: "#00ccff" }]
        }) });
        var container = hairlineBox(box);
        verify(container);
        var lines = childRects(container);
        compare(lines.length, 1);
        verify(Qt.colorEqual(lines[0].color, "#00ccff"));
        compare(lines[0].width, 1);
        compare(lines[0].height, container.height);
        compare(lines[0].x, container.width - 1);
        // A border of its own sits outside the line, so the two never
        // paint over one another.
        compare(container.anchors.margins, 1);
    }

    function test_a_box_with_no_hairlines_draws_none() {
        var box = make({ role: "card" });
        compare(childRects(hairlineBox(box)).length, 0);
    }

    function test_a_face_draws_a_gradient_only_when_the_table_sets_one() {
        var plain = make({ role: "card" });
        compare(faceLoader(plain).item, null);

        var box = make({ box: resolved({
            fill: "#151515",
            border: { color: "#444444", width: 1 },
            face: { from: "#ffffff", to: "#00000000" }
        }) });
        var loader = faceLoader(box);
        verify(loader.item);
        verify(loader.item.gradient);
        compare(loader.item.radius, 8 - 1);
    }

    // A cast is the one layer that costs a shader, so nothing instantiates
    // one until a table asks for a blurred layer.
    function test_a_cast_instantiates_an_effect_only_when_a_layer_blurs() {
        compare(effects(make({ role: "card" })).length, 0);
        compare(effects(make({ role: "cursor" })).length, 0);

        var box = make({ box: resolved({
            fill: "#151515",
            casts: [{ x: 0, y: 3, blur: 4, spread: 0, color: "#00000026" }]
        }) });
        var cast = effects(box);
        compare(cast.length, 1);
        verify(cast[0].shadowEnabled);
        verify(cast[0].maskEnabled);
        verify(cast[0].maskInverted);
        verify(!cast[0].autoPaddingEnabled);
        compare(cast[0].shadowVerticalOffset, 3);
        verify(Qt.colorEqual(cast[0].shadowColor, "#00000026"));
        // The silhouette is padded by what the cast reaches, and it is the
        // source and the mask both.
        compare(cast[0].source, box.children[0]);
        compare(cast[0].maskSource, box.children[0]);
        compare(box.children[0].width, box.width + (4 + 3) * 2);
    }

    // --- The wash --------------------------------------------------------

    function test_the_pointer_wash_lands_over_the_fill() {
        var box = make({ role: "cell", state: "hover" });
        var drawn = visibleRects(box);
        compare(drawn.length, 2);
        verify(Qt.colorEqual(drawn[1].color, Theme.hoverFill));
        tryCompare(drawn[1], "opacity", 1);
        compare(drawn[1].radius, Theme.radiusMd);
    }

    // A variant carrying a colour of its own blends toward `background`
    // instead, so the wash never reaches it.
    function test_a_tinted_state_carries_no_wash() {
        var box = make({ role: "button.default", state: "hover" });
        compare(visibleRects(box).length, 1);
        verify(Qt.colorEqual(visibleRects(box)[0].color, Theme.hoverFilled(Theme.color.primary)));
    }
}

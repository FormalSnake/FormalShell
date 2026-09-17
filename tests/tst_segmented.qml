import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Segmented's contract (spec "Picker"): a `muted` group at `radiusMd`, the
// selected segment filled `background` behind a 1px `border` at the
// concentric radius, the ring on `cursor`, and one `changed` per real move.
//
// Verified against a synthetic palette rather than Palette.fallback()'s own
// hex values, for the reason tst_button.qml documents: the zinc fallback
// shares a hex between roles, so a hex assertion could not tell a correct
// role from a swapped one.
TestCase {
    id: testCase
    name: "Segmented"
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
        muted: "#232323",
        accent: "#2a2a2a",
        accentForeground: "#dddddd",
        primary: "#1133ff",
        primaryForeground: "#ffdd00",
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
        id: segmentedComponent
        Segmented {}
    }

    Component {
        id: spyComponent
        SignalSpy {}
    }

    function make(props) {
        var control = createTemporaryObject(segmentedComponent, testCase, props);
        verify(control);
        waitForRendering(control);
        return control;
    }

    // The control's own children, in declaration order: the trough, the one
    // selection chip that travels between segments, and the segment row. The
    // first two are `Box`es, so their fill and the cursor's halo are the
    // rectangles Box draws inside them (tst_box.qml walks the same shape):
    // the halo when there is one, then the fill, then the pointer's wash.
    function trough(control) { return control.children[0]; }
    function selection(control) { return control.children[1]; }
    function row(control) { return control.children[2]; }

    function boxRects(box) {
        var out = [];
        for (var i = 0; i < box.children.length; i++) {
            var child = box.children[i];
            if (child.radius !== undefined && child.border !== undefined)
                out.push(child);
        }
        return out;
    }

    function fillOf(box) {
        var all = boxRects(box);
        return all[all.length - 2];
    }

    function haloOf(box) {
        var all = boxRects(box);
        return all.length > 2 ? all[0] : null;
    }

    function group(control) { return fillOf(trough(control)); }
    function chip(control) { return fillOf(selection(control)); }

    function segment(control, index) {
        var items = row(control).children;
        // A Repeater is a child of the Row alongside the items it created.
        var out = [];
        for (var i = 0; i < items.length; i++) {
            if (items[i].width !== undefined && items[i].children.length > 0)
                out.push(items[i]);
        }
        return out[index];
    }

    // A segment's own layers, in declaration order: the pointer wash and the
    // label. The chosen-segment fill is no longer one of them; it is the
    // single `selection` rectangle above, which travels between them.
    function washOf(seg) { return seg.children[0]; }
    function labelOf(seg) { return seg.children[1]; }

    function test_the_group_is_muted_at_radius_md() {
        var control = make({ options: ["DARK", "LIGHT"] });
        var body = group(control);
        verify(Qt.colorEqual(body.color, Theme.color.muted));
        compare(body.radius, Theme.radiusMd);
        compare(body.border.width, 0);
        compare(control.implicitHeight, Theme.space.controlHeight);
    }

    function test_the_selected_segment_is_background_behind_a_border() {
        var control = make({ options: ["DARK", "LIGHT"] });
        var on = selection(control);
        verify(on.visible);
        verify(Qt.colorEqual(chip(control).color, Theme.color.background));
        compare(chip(control).border.width, Theme.borderWidth);
        verify(Qt.colorEqual(chip(control).border.color, Theme.color.border));
        // One rectangle covering the chosen segment, not one per segment:
        // it sits on the first segment's own box, inset by the padding.
        compare(on.x, control.padding);
        compare(on.width, control._segmentWidth);
        compare(on.height, control.height - control.padding * 2);
    }

    // The concentric rule (spec "Radius"): the outer radius minus the padding
    // between them, floored at radiusSm.
    function test_the_segment_radius_is_concentric() {
        var control = make({ options: ["DARK", "LIGHT"] });
        var concentric = Math.max(Theme.radiusSm, Theme.radiusMd - control.padding);
        compare(selection(control).radius, concentric);
        compare(chip(control).radius, concentric);
    }

    // M53 D2: the selection travels to the next segment rather than being
    // redrawn there, so it is still short of its target on the tick the
    // index changes.
    function test_the_selection_travels_to_the_chosen_segment() {
        var control = make({ options: ["DARK", "LIGHT"] });
        var on = selection(control);
        control.select(1);
        compare(on.x, control.padding);
        tryCompare(on, "x", control.padding + control._segmentWidth, 1000);
    }

    function test_no_options_draws_no_selection() {
        verify(!selection(make({ options: [] })).visible);
    }

    function test_labels_are_sans_and_the_selected_one_is_not_muted() {
        var control = make({ options: ["DARK", "LIGHT"] });
        compare(labelOf(segment(control, 0)).font.family, Theme.fontFamilySans);
        verify(Qt.colorEqual(labelOf(segment(control, 0)).color, Theme.color.foreground));
        verify(Qt.colorEqual(labelOf(segment(control, 1)).color, Theme.color.mutedForeground));
    }

    function test_every_segment_is_the_width_of_the_widest_label() {
        var control = make({ options: ["DARK", "LIGHT"] });
        compare(segment(control, 0).width, segment(control, 1).width);
        compare(control.implicitWidth, control._segmentWidth * 2 + control.padding * 2);
    }

    function test_select_moves_the_index_and_reports_once() {
        var control = make({ options: ["DARK", "LIGHT"] });
        var spy = createTemporaryObject(spyComponent, testCase, { target: control, signalName: "changed" });
        control.select(1);
        compare(control.index, 1);
        compare(spy.count, 1);
        compare(spy.signalArguments[0][0], 1);
    }

    function test_selecting_what_is_already_selected_reports_nothing() {
        var control = make({ options: ["DARK", "LIGHT"] });
        var spy = createTemporaryObject(spyComponent, testCase, { target: control, signalName: "changed" });
        control.select(0);
        compare(spy.count, 0);
    }

    function test_out_of_range_is_refused_rather_than_clamped() {
        var control = make({ options: ["DARK", "LIGHT"] });
        control.select(5);
        compare(control.index, 0);
        control.select(-1);
        compare(control.index, 0);
    }

    function test_step_clamps_at_both_ends() {
        var control = make({ options: ["DARK", "LIGHT"] });
        control.step(-1);
        compare(control.index, 0);
        control.step(1);
        compare(control.index, 1);
        control.step(1);
        compare(control.index, 1);
    }

    function test_a_click_selects_that_segment() {
        var control = make({ options: ["DARK", "LIGHT"] });
        var spy = createTemporaryObject(spyComponent, testCase, { target: control, signalName: "changed" });
        var target = segment(control, 1);
        mouseClick(target, target.width / 2, target.height / 2);
        compare(control.index, 1);
        compare(spy.count, 1);
    }

    function test_cursor_draws_the_ring() {
        var control = make({ options: ["DARK", "LIGHT"], cursor: true });
        var halo = haloOf(trough(control));
        verify(halo.visible);
        // The table's own ring layer: filled at that layer's alpha rather
        // than opaque under a 0.5 opacity, the same band of pixels.
        verify(Qt.colorEqual(halo.color, Qt.alpha(Theme.color.ring, testCase.ringAlpha)));
        compare(halo.opacity, 1);
        compare(group(control).border.width, Theme.borderWidth);
        verify(Qt.colorEqual(group(control).border.color, Theme.color.ring));

        var resting = make({ options: ["DARK", "LIGHT"] });
        compare(haloOf(trough(resting)), null);
    }

    // The group used to take the hand cursor and answer nothing on an
    // unchosen segment.
    function test_hovering_an_unchosen_segment_washes_it_and_lifts_its_ink() {
        var control = make({ options: ["DARK", "LIGHT"] });
        var target = segment(control, 1);
        compare(washOf(target).opacity, 0);
        verify(Qt.colorEqual(labelOf(target).color, Theme.color.mutedForeground));

        mouseMove(target, target.width / 2, target.height / 2);
        tryCompare(washOf(target), "opacity", 1);
        verify(Qt.colorEqual(washOf(target).color, Theme.hoverFill));
        verify(Qt.colorEqual(labelOf(target).color, Theme.color.foreground));

        // The chosen one states itself already, so the pointer adds nothing.
        var chosen = segment(control, 0);
        mouseMove(chosen, chosen.width / 2, chosen.height / 2);
        tryCompare(washOf(chosen), "opacity", 0);
    }

    function test_no_options_is_inert_rather_than_broken() {
        var control = make({ options: [] });
        compare(control.count, 0);
        control.step(1);
        compare(control.index, 0);
    }
}

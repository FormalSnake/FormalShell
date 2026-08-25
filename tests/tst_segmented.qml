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

    // The painted layers in declaration order: ring halo, group, segment row.
    function halo(control) { return control.children[0]; }
    function group(control) { return control.children[1]; }
    function row(control) { return control.children[2]; }

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

    function fillOf(seg) { return seg.children[0]; }
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
        var on = fillOf(segment(control, 0));
        verify(on.visible);
        verify(Qt.colorEqual(on.color, Theme.color.background));
        compare(on.border.width, Theme.borderWidth);
        verify(Qt.colorEqual(on.border.color, Theme.color.border));
        verify(!fillOf(segment(control, 1)).visible);
    }

    // The concentric rule (spec "Radius"): the outer radius minus the padding
    // between them, floored at radiusSm.
    function test_the_segment_radius_is_concentric() {
        var control = make({ options: ["DARK", "LIGHT"] });
        compare(fillOf(segment(control, 0)).radius,
                Math.max(Theme.radiusSm, Theme.radiusMd - control.padding));
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
        verify(halo(control).visible);
        verify(Qt.colorEqual(halo(control).color, Theme.color.ring));
        compare(halo(control).opacity, Theme.ringAlpha);
        compare(group(control).border.width, Theme.borderWidth);
        verify(Qt.colorEqual(group(control).border.color, Theme.color.ring));

        var resting = make({ options: ["DARK", "LIGHT"] });
        verify(!halo(resting).visible);
    }

    function test_no_options_is_inert_rather_than_broken() {
        var control = make({ options: [] });
        compare(control.count, 0);
        control.step(1);
        compare(control.index, 0);
    }
}

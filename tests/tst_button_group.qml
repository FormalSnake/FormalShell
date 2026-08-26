import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// ButtonGroup's contract (DESIGN.md §2, M48 D1): a `muted` trough at
// `radiusMd` holding one `Button` per option, the selected one painted the
// segmented way when the group is exclusive, the ring on the cursor button,
// `changed` only on a press that moves the selection, and `pressed` on every
// press.
//
// Verified against a synthetic palette rather than Palette.fallback()'s own
// hex values, for the reason tst_button.qml documents: the zinc fallback
// shares a hex between roles, so a hex assertion could not tell a correct
// role from a swapped one.
TestCase {
    id: testCase
    name: "ButtonGroup"
    width: 500
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
        destructive: "#ff2222",
        destructiveForeground: "#22ff88",
        ring: "#00ccff"
    })

    readonly property var profileOptions: [
        { icon: "leaf", label: "Power Saver", value: "saver" },
        { icon: "gauge", label: "Balanced", value: "balanced" },
        { icon: "zap", label: "Performance", value: "performance" }
    ]

    property var _originalColor

    function init() {
        testCase._originalColor = Theme.color;
        Theme.color = testCase.sentinelColors;
    }

    function cleanup() {
        Theme.color = testCase._originalColor;
    }

    Component {
        id: groupComponent
        ButtonGroup {}
    }

    Component {
        id: spyComponent
        SignalSpy {}
    }

    function make(props) {
        var group = createTemporaryObject(groupComponent, testCase, props);
        verify(group);
        waitForRendering(group);
        wait(50);
        return group;
    }

    // The trough is the group's first child; the buttons live in the Row
    // after it, alongside the Repeater that created them.
    function trough(group) { return group.children[0]; }

    function buttons(group) {
        var row = group.children[1];
        var out = [];
        for (var i = 0; i < row.children.length; i++) {
            if (row.children[i].variant !== undefined)
                out.push(row.children[i]);
        }
        return out;
    }

    function body(button) {
        var out = [];
        for (var i = 0; i < button.children.length; i++) {
            var child = button.children[i];
            if (child.radius !== undefined && child.border !== undefined)
                out.push(child);
        }
        return out[1];
    }

    function test_the_trough_is_muted_at_the_control_radius() {
        var group = make({ options: testCase.profileOptions });
        verify(Qt.colorEqual(trough(group).color, Theme.color.muted));
        compare(trough(group).radius, Theme.radiusMd);
    }

    function test_one_button_per_option() {
        var group = make({ options: testCase.profileOptions });
        compare(group.count, 3);
        compare(buttons(group).length, 3);
    }

    function test_buttons_are_ghost_and_the_selected_one_is_segmented() {
        var group = make({ options: testCase.profileOptions, index: 1 });
        var items = buttons(group);
        compare(items[0].variant, "ghost");
        compare(items[1].variant, "selected");
        compare(items[2].variant, "ghost");
        // The segmented look: `background` behind a 1px `border`.
        verify(Qt.colorEqual(body(items[1]).color, Theme.color.background));
        compare(body(items[1]).border.width, Theme.borderWidth);
        verify(Qt.colorEqual(body(items[1]).border.color, Theme.color.border));
        compare(body(items[0]).color.a, 0);
    }

    function test_a_non_exclusive_group_selects_nothing_and_fills_actives() {
        var group = make({
            exclusive: false,
            index: 0,
            options: [
                { icon: "shuffle", active: true },
                { icon: "repeat" }
            ]
        });
        var items = buttons(group);
        // index means nothing here: the on-state is the option's own.
        compare(items[0].variant, "default");
        compare(items[1].variant, "ghost");
    }

    function test_the_button_radius_is_the_trough_minus_its_padding() {
        var group = make({ options: testCase.profileOptions });
        compare(buttons(group)[0].radius,
            Math.max(Theme.radiusSm, Theme.radiusMd - group.padding));
    }

    function test_every_button_is_the_same_width() {
        var group = make({ options: testCase.profileOptions, width: 360 });
        var items = buttons(group);
        compare(items[0].width, items[1].width);
        compare(items[1].width, items[2].width);
        // The three buttons plus the trough padding either side and between
        // them fill the width the group was given.
        compare(Math.round(items[0].width * 3 + group.padding * 4), 360);
    }

    function test_the_ring_lands_on_the_cursor_button_only() {
        var group = make({ options: testCase.profileOptions, cursor: true, cursorIndex: 2 });
        var items = buttons(group);
        verify(!items[0].cursor);
        verify(!items[1].cursor);
        verify(items[2].cursor);
    }

    function test_no_ring_at_all_while_the_cursor_is_hidden() {
        var group = make({ options: testCase.profileOptions, cursorIndex: 2 });
        verify(!buttons(group)[2].cursor);
    }

    function test_step_walks_the_cursor_and_clamps_at_both_ends() {
        var group = make({ options: testCase.profileOptions, cursorIndex: 0 });
        group.step(1);
        compare(group.cursorIndex, 1);
        group.step(-1);
        compare(group.cursorIndex, 0);
        group.step(-1);
        compare(group.cursorIndex, 0);
        group.cursorIndex = 2;
        group.step(1);
        compare(group.cursorIndex, 2);
    }

    function test_a_press_that_moves_the_selection_reports_both_signals() {
        var group = make({ options: testCase.profileOptions, index: 0 });
        var changed = createTemporaryObject(spyComponent, testCase,
            { target: group, signalName: "changed" });
        var pressed = createTemporaryObject(spyComponent, testCase,
            { target: group, signalName: "pressed" });
        group.press(2);
        compare(changed.count, 1);
        compare(changed.signalArguments[0][0], 2);
        compare(pressed.count, 1);
    }

    // Controlled, never self-writing: the owner holds the selection, so a
    // press leaves `index` where the owner put it.
    function test_a_press_never_writes_the_index_itself() {
        var group = make({ options: testCase.profileOptions, index: 0 });
        group.press(2);
        compare(group.index, 0);
    }

    function test_pressing_the_selected_option_reports_pressed_only() {
        var group = make({ options: testCase.profileOptions, index: 1 });
        var changed = createTemporaryObject(spyComponent, testCase,
            { target: group, signalName: "changed" });
        var pressed = createTemporaryObject(spyComponent, testCase,
            { target: group, signalName: "pressed" });
        group.press(1);
        compare(changed.count, 0);
        compare(pressed.count, 1);
    }

    function test_a_disabled_option_answers_nothing() {
        var group = make({
            options: [{ label: "On" }, { label: "Off", enabled: false }],
            index: 0
        });
        var pressed = createTemporaryObject(spyComponent, testCase,
            { target: group, signalName: "pressed" });
        group.press(1);
        compare(pressed.count, 0);
        compare(buttons(group)[1].enabled, false);
    }

    function test_activate_presses_the_cursor_button() {
        var group = make({ options: testCase.profileOptions, index: 0, cursorIndex: 2 });
        var changed = createTemporaryObject(spyComponent, testCase,
            { target: group, signalName: "changed" });
        group.activate();
        compare(changed.count, 1);
        compare(changed.signalArguments[0][0], 2);
    }

    function test_a_click_presses_the_button_under_the_pointer() {
        var group = make({ options: testCase.profileOptions, index: 0, width: 360 });
        var pressed = createTemporaryObject(spyComponent, testCase,
            { target: group, signalName: "pressed" });
        var last = buttons(group)[2];
        mouseClick(last, last.width / 2, last.height / 2);
        compare(pressed.count, 1);
        compare(pressed.signalArguments[0][0], 2);
    }

    function test_an_empty_group_has_no_width_and_no_buttons() {
        var group = make({ options: [] });
        compare(group.count, 0);
        compare(group.implicitWidth, 0);
        compare(buttons(group).length, 0);
    }
}

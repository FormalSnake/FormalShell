import QtQuick
import QtTest
import "../shell/Compositor/keyboard.js" as Keyboard

TestCase {
    name: "KeyboardLayout"

    // Hyprland field names are UNVERIFIED (see keyboard.js's
    // header): `layout` is a comma-separated xkb code list, `active_keymap`
    // is the human name of the live one.
    readonly property string hyprlandFixture: JSON.stringify({
        mice: [],
        keyboards: [
            { name: "virtual-keyboard", layout: "us", active_keymap: "English (US)", main: false },
            { name: "at-translated-set-2-keyboard", layout: "us,de", active_keymap: "German", main: true }
        ],
        tablets: [],
        touch: [],
        switches: []
    })

    function test_current_layout_returns_the_indexed_name() {
        compare(Keyboard.currentLayout(["English (US)", "German"], 1), "German");
    }

    function test_current_layout_out_of_range_index_is_empty_never_the_first_name() {
        compare(Keyboard.currentLayout(["English (US)", "German"], 5), "");
        compare(Keyboard.currentLayout(["English (US)", "German"], -1), "");
    }

    function test_current_layout_of_empty_names_is_empty() {
        compare(Keyboard.currentLayout([], 0), "");
        compare(Keyboard.currentLayout(undefined, 0), "");
    }

    function test_short_label_extracts_the_parenthetical_region_uppercased() {
        compare(Keyboard.shortLabel("English (US)"), "US");
        compare(Keyboard.shortLabel("English (US, intl., with dead keys)"), "US");
    }

    function test_short_label_falls_back_to_first_two_letters_when_no_parenthetical() {
        compare(Keyboard.shortLabel("German"), "GE");
        compare(Keyboard.shortLabel("de"), "DE");
    }

    function test_short_label_of_empty_is_empty() {
        compare(Keyboard.shortLabel(""), "");
        compare(Keyboard.shortLabel(undefined), "");
    }

    function test_unavailable_is_the_shared_honest_empty_shape() {
        var l = Keyboard.unavailable();
        compare(l.available, false);
        compare(l.names.length, 0);
        compare(l.currentIdx, -1);
        compare(l.current, "");
    }

    function test_hyprland_reads_the_main_keyboard_not_the_first_listed() {
        var l = Keyboard.parseHyprlandLayouts(hyprlandFixture);
        compare(l.available, true);
        compare(l.names.length, 2);
        compare(l.names[0], "us");
        compare(l.names[1], "de");
        compare(l.current, "German");
    }

    function test_hyprland_reports_no_index_because_codes_and_keymap_names_do_not_map() {
        compare(Keyboard.parseHyprlandLayouts(hyprlandFixture).currentIdx, -1);
    }

    function test_hyprland_falls_back_to_the_first_keyboard_when_none_is_main() {
        var fixture = JSON.stringify({
            keyboards: [{ name: "kb", layout: "fr", active_keymap: "French", main: false }]
        });
        var l = Keyboard.parseHyprlandLayouts(fixture);
        compare(l.available, true);
        compare(l.current, "French");
    }

    function test_hyprland_with_no_keyboards_or_bad_output_is_unavailable() {
        compare(Keyboard.parseHyprlandLayouts(JSON.stringify({ keyboards: [] })).available, false);
        compare(Keyboard.parseHyprlandLayouts("").available, false);
        compare(Keyboard.parseHyprlandLayouts("Invalid command").available, false);
    }

    function test_has_choice_gates_the_cell_on_more_than_one_layout() {
        compare(Keyboard.hasChoice(Keyboard.parseHyprlandLayouts(hyprlandFixture)), true);
        compare(Keyboard.hasChoice(Keyboard.parseHyprlandLayouts(JSON.stringify({
            keyboards: [{ name: "kb", layout: "us", active_keymap: "English (US)", main: true }]
        }))), false);
        compare(Keyboard.hasChoice(Keyboard.unavailable()), false);
    }

    // The active layout leads, with a known index or without one.
    function test_tooltip_lists_every_layout_with_the_active_one_first() {
        compare(Keyboard.tooltipText({ available: true, names: ["English (US)", "German"], currentIdx: 1, current: "German" }),
            "GERMAN / ENGLISH (US)");
    }

    function test_tooltip_without_a_known_index_leads_with_the_active_keymap() {
        compare(Keyboard.tooltipText(Keyboard.parseHyprlandLayouts(hyprlandFixture)), "GERMAN / US / DE");
    }

    function test_tooltip_of_an_unavailable_backend_is_no_layout() {
        compare(Keyboard.tooltipText(Keyboard.unavailable()), "NO LAYOUT");
        compare(Keyboard.tooltipText(undefined), "NO LAYOUT");
    }

    function test_apply_active_layout_sets_current_from_the_event_data() {
        var l = Keyboard.parseHyprlandLayouts(hyprlandFixture);
        var updated = Keyboard.applyActiveLayout(l, "at-translated-set-2-keyboard,English (US)");
        compare(updated.available, true);
        compare(updated.current, "English (US)");
        compare(updated.names, l.names);
    }

    function test_apply_active_layout_leaves_an_unavailable_layout_untouched() {
        var l = Keyboard.unavailable();
        compare(Keyboard.applyActiveLayout(l, "kb,German"), l);
    }

    function test_apply_active_layout_with_no_comma_leaves_the_layout_unchanged() {
        var l = Keyboard.parseHyprlandLayouts(hyprlandFixture);
        compare(Keyboard.applyActiveLayout(l, "nocommahere"), l);
    }
}

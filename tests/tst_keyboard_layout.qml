import QtQuick
import QtTest
import "../shell/Compositor/keyboard.js" as Keyboard

TestCase {
    name: "KeyboardLayout"

    // Shape lifted from the pinned niri source rather than invented: `niri
    // msg --json keyboard-layouts` prints the bare KeyboardLayouts struct
    // (src/ipc/client.rs:390-400), and the names are xkb.layout_name()
    // output (src/ipc/server.rs:535-546), not xkb codes.
    readonly property string niriFixture: JSON.stringify({
        names: ["English (US)", "German"],
        current_idx: 1
    })

    // Hyprland field names are the UNVERIFIED half (see keyboard.js's
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

    function test_niri_output_parses_names_and_the_active_index() {
        var l = Keyboard.parseNiriLayouts(niriFixture);
        compare(l.available, true);
        compare(l.names.length, 2);
        compare(l.names[0], "English (US)");
        compare(l.currentIdx, 1);
        compare(l.current, "German");
    }

    function test_niri_out_of_range_index_reports_no_current_layout_not_the_first() {
        var l = Keyboard.parseNiriLayouts(JSON.stringify({ names: ["English (US)"], current_idx: 7 }));
        compare(l.available, true);
        compare(l.currentIdx, -1);
        compare(l.current, "");
    }

    function test_niri_unparsable_output_is_unavailable_never_a_guessed_layout() {
        compare(Keyboard.parseNiriLayouts("").available, false);
        compare(Keyboard.parseNiriLayouts("Keyboard layouts:\n * 0 English (US)\n").available, false);
        compare(Keyboard.parseNiriLayouts(JSON.stringify({ ok: true })).available, false);
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
        compare(Keyboard.hasChoice(Keyboard.parseNiriLayouts(niriFixture)), true);
        compare(Keyboard.hasChoice(Keyboard.parseNiriLayouts(JSON.stringify({ names: ["English (US)"], current_idx: 0 }))), false);
        compare(Keyboard.hasChoice(Keyboard.unavailable()), false);
    }

    function test_tooltip_lists_every_layout_with_the_active_one_first() {
        compare(Keyboard.tooltipText(Keyboard.parseNiriLayouts(niriFixture)), "GERMAN / ENGLISH (US)");
    }

    function test_tooltip_without_a_known_index_leads_with_the_active_keymap() {
        compare(Keyboard.tooltipText(Keyboard.parseHyprlandLayouts(hyprlandFixture)), "GERMAN / US / DE");
    }

    function test_tooltip_of_an_unavailable_backend_is_no_layout() {
        compare(Keyboard.tooltipText(Keyboard.unavailable()), "NO LAYOUT");
        compare(Keyboard.tooltipText(undefined), "NO LAYOUT");
    }
}

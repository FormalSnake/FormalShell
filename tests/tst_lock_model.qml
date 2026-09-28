import QtQuick
import QtTest
import "../shell/Lock/model.js" as Model

// The lock surface's pure half: the ink the words on the wallpaper take,
// chosen by contrast with the wallpaper under the scrim, and the transport
// cursor the password field's key filter drives without ever giving up
// focus.
TestCase {
    name: "LockModel"

    function stats(mean) {
        return { mean: mean, std: 0, acutance: 0, sampled: true };
    }

    // --- Ink -------------------------------------------------------------

    function test_a_dark_wallpaper_takes_light_ink() {
        compare(Model.ink(stats(30), 0.5, 0), "light");
        compare(Model.ink(stats(30), 0, 0), "light");
    }

    // The scrim is what the words actually sit on: a white field under
    // black at 0.5 is mid grey, where black words out-contrast white ones.
    function test_a_white_wallpaper_under_the_scrim_takes_dark_ink() {
        compare(Model.ink(stats(255), 0.5, 0), "dark");
    }

    // A bright but not white field under the same scrim lands below the
    // crossover (~118 after the scrim) and keeps light ink.
    function test_the_scrim_moves_the_crossover() {
        compare(Model.ink(stats(230), 0.5, 0), "light");
        compare(Model.ink(stats(230), 0, 0), "dark");
    }

    function test_the_crossover_sits_near_118() {
        compare(Model.ink(stats(112), 0, 0), "light");
        compare(Model.ink(stats(124), 0, 0), "dark");
    }

    // Nothing sampled reads the fallback, which is the flat colour the
    // surface fills with instead.
    function test_an_unsampled_wallpaper_reads_the_fallback() {
        var none = { mean: 0, std: 0, acutance: 0, sampled: false };
        compare(Model.ink(none, 0.5, 250), "dark");
        compare(Model.ink(none, 0.5, 10), "light");
        compare(Model.ink(null, 0.5, 250), "dark");
        compare(Model.backdropLuma(none, 0.5, 42), 42);
    }

    function test_backdrop_luma_is_the_mean_under_black_at_the_scrim() {
        fuzzyCompare(Model.backdropLuma(stats(200), 0.5, 0), 100, 0.001);
        fuzzyCompare(Model.backdropLuma(stats(200), 0, 0), 200, 0.001);
    }

    function test_luma_of_a_colour() {
        fuzzyCompare(Model.lumaOf(1, 1, 1), 255, 0.001);
        fuzzyCompare(Model.lumaOf(0, 0, 0), 0, 0.001);
    }

    // --- The transport cursor --------------------------------------------

    function test_tab_walks_the_buttons_and_falls_back_to_the_field() {
        var s = Model.transportKey(-1, 3, "tab");
        compare(s.index, 0);
        verify(s.taken);
        s = Model.transportKey(2, 3, "tab");
        compare(s.index, -1);
        verify(s.taken);
    }

    function test_backtab_walks_back_from_the_field_to_the_last_button() {
        compare(Model.transportKey(-1, 3, "backtab").index, 2);
        compare(Model.transportKey(0, 3, "backtab").index, -1);
    }

    // With the cursor off every other key is the field's.
    function test_the_field_keeps_its_keys_while_the_cursor_is_off() {
        var keys = ["left", "right", "enter", "escape", "other"];
        for (var i = 0; i < keys.length; i++) {
            var s = Model.transportKey(-1, 3, keys[i]);
            compare(s.index, -1, keys[i]);
            verify(!s.taken, keys[i]);
            verify(!s.press, keys[i]);
        }
    }

    function test_arrows_step_clamped_while_the_cursor_is_on() {
        compare(Model.transportKey(0, 3, "left").index, 0);
        compare(Model.transportKey(0, 3, "right").index, 1);
        compare(Model.transportKey(2, 3, "right").index, 2);
        verify(Model.transportKey(1, 3, "left").taken);
    }

    function test_enter_presses_the_button_under_the_cursor() {
        var s = Model.transportKey(1, 3, "enter");
        compare(s.index, 1);
        verify(s.press);
        verify(s.taken);
    }

    function test_escape_hands_the_cursor_back() {
        var s = Model.transportKey(1, 3, "escape");
        compare(s.index, -1);
        verify(s.taken);
    }

    // Typing always reaches the password: the character is not taken, and
    // the cursor goes back to the field with it.
    function test_a_typed_character_goes_to_the_field() {
        var s = Model.transportKey(1, 3, "other");
        compare(s.index, -1);
        verify(!s.taken);
        verify(!s.press);
    }

    // Shift on its own is half of Backtab and must not drop the cursor.
    function test_a_modifier_alone_changes_nothing() {
        var s = Model.transportKey(1, 3, "modifier");
        compare(s.index, 1);
        verify(!s.taken);
    }

    function test_no_buttons_means_no_cursor() {
        var s = Model.transportKey(1, 0, "tab");
        compare(s.index, -1);
        verify(!s.taken);
    }
}

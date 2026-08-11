import QtQuick
import QtTest
import "../shell/Compositor/appmatch.js" as AppMatch

TestCase {
    name: "AppMatch"

    function win(id, appId) {
        return { id: id, appId: appId, workspaceId: "ws1", title: "t" };
    }

    function entry(id, startupClass) {
        return { id: id, startupClass: startupClass, name: id };
    }

    function test_startup_class_beats_id_when_both_present() {
        var windows = [win("1", "firefox"), win("2", "org.mozilla.firefox")];
        var matches = AppMatch.matchWindows(entry("org.mozilla.firefox", "firefox"), windows);
        compare(matches.length, 1);
        compare(matches[0], "1");
    }

    function test_startup_class_matches_case_insensitively() {
        var windows = [win("1", "Alacritty")];
        var matches = AppMatch.matchWindows(entry("alacritty-terminal", "alacritty"), windows);
        compare(matches.length, 1);
        compare(matches[0], "1");
    }

    function test_exact_startup_class_wins_over_a_case_folded_one() {
        var windows = [win("1", "Alacritty"), win("2", "alacritty")];
        var matches = AppMatch.matchWindows(entry("alacritty", "alacritty"), windows);
        compare(matches.length, 1);
        compare(matches[0], "2");
    }

    function test_falls_back_to_entry_id_when_startup_class_is_empty() {
        var windows = [win("1", "mpv")];
        var matches = AppMatch.matchWindows(entry("mpv", ""), windows);
        compare(matches.length, 1);
        compare(matches[0], "1");
    }

    function test_no_match_returns_empty_list_so_the_caller_spawns() {
        var windows = [win("1", "firefox"), win("2", "mpv")];
        compare(AppMatch.matchWindows(entry("code", "code"), windows).length, 0);
    }

    function test_empty_app_id_on_a_window_never_matches_an_empty_startup_class() {
        var windows = [win("1", "")];
        compare(AppMatch.matchWindows(entry("", ""), windows).length, 0);
        compare(AppMatch.matchWindows(entry("mpv", ""), windows).length, 0);
    }

    function test_every_instance_of_the_same_app_is_matched_in_window_order() {
        var windows = [win("1", "kitty"), win("2", "mpv"), win("3", "kitty")];
        var matches = AppMatch.matchWindows(entry("kitty", "kitty"), windows);
        compare(matches.length, 2);
        compare(matches[0], "1");
        compare(matches[1], "3");
    }

    function test_next_window_cycles_past_the_focused_instance_and_wraps() {
        var matches = ["a", "b", "c"];
        compare(AppMatch.nextWindow(matches, "a"), "b");
        compare(AppMatch.nextWindow(matches, "b"), "c");
        compare(AppMatch.nextWindow(matches, "c"), "a");
    }

    function test_next_window_returns_first_when_focus_is_elsewhere_or_empty() {
        var matches = ["a", "b"];
        compare(AppMatch.nextWindow(matches, ""), "a");
        compare(AppMatch.nextWindow(matches, "zzz"), "a");
    }

    function test_next_window_of_empty_matches_is_empty_string() {
        compare(AppMatch.nextWindow([], "a"), "");
    }

    function test_window_ids_are_returned_verbatim_never_parsed() {
        var windows = [win("abc123def", "kitty"), win("0x55f1", "kitty")];
        var matches = AppMatch.matchWindows(entry("kitty", "kitty"), windows);
        compare(matches[0], "abc123def");
        compare(matches[1], "0x55f1");
        compare(AppMatch.nextWindow(matches, "abc123def"), "0x55f1");
    }

    function test_decorate_app_rows_marks_only_matched_rows_with_FOCUS() {
        var windows = [win("1", "firefox")];
        var rows = [
            { id: "apps.firefox", label: "Firefox", _entry: entry("firefox", "firefox") },
            { id: "apps.mpv", label: "mpv", _entry: entry("mpv", "mpv") }
        ];
        var decorated = AppMatch.decorateAppRows(rows, windows);
        compare(decorated.length, 2);
        compare(decorated[0].desc, "FOCUS");
        compare(decorated[0].label, "Firefox");
        compare(decorated[1].desc, undefined);
    }

    function test_decorate_app_rows_does_not_mutate_the_input_rows() {
        var windows = [win("1", "firefox")];
        var rows = [{ id: "apps.firefox", label: "Firefox", _entry: entry("firefox", "firefox") }];
        var before = JSON.stringify(rows);
        AppMatch.decorateAppRows(rows, windows);
        compare(JSON.stringify(rows), before);
    }

    function test_decorate_app_rows_with_no_windows_marks_nothing() {
        var rows = [{ id: "apps.mpv", label: "mpv", _entry: entry("mpv", "mpv") }];
        var decorated = AppMatch.decorateAppRows(rows, []);
        compare(decorated[0].desc, undefined);
    }
}

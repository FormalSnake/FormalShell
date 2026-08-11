import QtQuick
import QtTest
import "../shell/Reminders/model.js" as M

TestCase {
    name: "RemindersModel"

    function entry(id, dueAt, message) {
        return { id: id, message: message === undefined ? "m-" + id : message, setAt: 0, dueAt: dueAt };
    }

    function ids(list) {
        return list.map(function (e) { return e.id; }).join(",");
    }

    function test_parse_duration_units() {
        compare(M.parseDuration("25m"), 1500);
        compare(M.parseDuration("90s"), 90);
        compare(M.parseDuration("1h"), 3600);
        compare(M.parseDuration("2h5m30s"), 7530);
    }

    function test_parse_duration_bare_only_token_is_minutes() {
        compare(M.parseDuration("10"), 600);
    }

    function test_parse_duration_bare_after_unit_takes_next_smaller_unit() {
        compare(M.parseDuration("1h30"), 5400);
        compare(M.parseDuration("5m30"), 330);
        // Bare after `m` is seconds, so this is 1h + 30m + 20s.
        compare(M.parseDuration("1h30m20"), 5420);
    }

    function test_parse_duration_bare_after_seconds_is_invalid() {
        compare(M.parseDuration("30s10"), null);
    }

    function test_parse_duration_rejects_non_durations() {
        compare(M.parseDuration(""), null);
        compare(M.parseDuration("abc"), null);
        compare(M.parseDuration("10x"), null);
        compare(M.parseDuration("-5"), null);
    }

    function test_parse_duration_rejects_zero() {
        compare(M.parseDuration("0"), null);
        compare(M.parseDuration("0m"), null);
    }

    function test_parse_duration_rejects_internal_whitespace() {
        // parseSpec has already split the message off, so a space inside the
        // duration token is a typo rather than a separator.
        compare(M.parseDuration("5 m"), null);
    }

    function test_parse_duration_max_boundary() {
        compare(M.parseDuration("720h"), M.MAX_DURATION_SECONDS);
        compare(M.parseDuration("721h"), null);
    }

    function test_parse_duration_is_case_insensitive() {
        compare(M.parseDuration("25M"), 1500);
    }

    function test_parse_spec_splits_duration_from_message() {
        var s = M.parseSpec("25m coffee break");
        compare(s.seconds, 1500);
        compare(s.message, "coffee break");
    }

    function test_parse_spec_without_message() {
        var s = M.parseSpec("10");
        compare(s.seconds, 600);
        compare(s.message, "");
    }

    function test_parse_spec_trims_surrounding_whitespace() {
        var s = M.parseSpec("  25m   coffee  ");
        compare(s.seconds, 1500);
        compare(s.message, "coffee");
    }

    function test_parse_spec_rejects_message_first() {
        compare(M.parseSpec("coffee 25m"), null);
        compare(M.parseSpec(""), null);
    }

    function test_make_entry_shape() {
        var e = M.makeEntry(1500, "coffee", 1000, 3);
        compare(e.id, "rem-1000-3");
        compare(e.message, "coffee");
        compare(e.setAt, 1000);
        compare(e.dueAt, 1000 + 1500 * 1000);
    }

    function test_add_keeps_list_sorted_by_due_at() {
        var list = [];
        list = M.add(list, entry("b", 3000));
        list = M.add(list, entry("a", 1000));
        list = M.add(list, entry("c", 2000));
        compare(ids(list), "a,c,b");
    }

    function test_add_does_not_mutate_input() {
        var list = [entry("b", 3000)];
        M.add(list, entry("a", 1000));
        compare(list.length, 1);
        compare(list[0].id, "b");
    }

    function test_normalize_drops_malformed_entries() {
        var raw = [
            entry("a", 2000),
            { message: "no id", dueAt: 1000 },
            { id: "no-due" },
            { id: "bad-due", dueAt: "soon" },
            null,
            entry("b", 1000)
        ];
        compare(ids(M.normalize(raw)), "b,a");
    }

    function test_normalize_of_non_array_is_empty() {
        compare(M.normalize(undefined).length, 0);
        compare(M.normalize(null).length, 0);
        compare(M.normalize({ id: "a", dueAt: 1 }).length, 0);
    }

    function test_normalize_does_not_mutate_input() {
        var raw = [entry("b", 3000), entry("a", 1000)];
        M.normalize(raw);
        compare(ids(raw), "b,a");
    }

    function test_normalize_fills_missing_set_at_from_due_at() {
        var list = M.normalize([{ id: "a", message: "x", dueAt: 5000 }]);
        compare(list[0].setAt, 5000);
    }

    function test_due_returns_same_remaining_identity_when_nothing_fired() {
        // The service's 1s tick skips its state.json write on this identity.
        var list = [entry("a", 5000)];
        var split = M.due(list, 1000);
        compare(split.fired.length, 0);
        verify(split.remaining === list);
    }

    function test_due_splits_fired_from_remaining() {
        var list = [entry("a", 1000), entry("b", 5000)];
        var split = M.due(list, 2000);
        compare(ids(split.fired), "a");
        compare(ids(split.remaining), "b");
        verify(split.remaining !== list);
    }

    function test_due_fires_entry_whose_due_time_passed_while_shell_was_down() {
        var list = [entry("stale", 1000)];
        var split = M.due(list, 1000 + 6 * 60 * 60 * 1000);
        compare(ids(split.fired), "stale");
        compare(split.remaining.length, 0);
    }

    function test_due_fires_several_at_once_in_due_at_order() {
        var list = [entry("a", 1000), entry("b", 2000), entry("c", 9000)];
        var split = M.due(list, 5000);
        compare(ids(split.fired), "a,b");
        compare(ids(split.remaining), "c");
    }

    function test_remaining_seconds_rounds_up_and_floors_at_zero() {
        compare(M.remainingSeconds(entry("a", 10500), 10000), 1);
        compare(M.remainingSeconds(entry("a", 10000), 10000), 0);
        compare(M.remainingSeconds(entry("a", 1000), 99000), 0);
    }

    function test_countdown_label_widths() {
        compare(M.countdownLabel(0), "00:00");
        compare(M.countdownLabel(65), "01:05");
        compare(M.countdownLabel(3599), "59:59");
        compare(M.countdownLabel(3600), "1:00:00");
        compare(M.countdownLabel(90000), "25:00:00");
    }

    function test_bar_label_empty_list() {
        compare(M.barLabel([], 0), "");
        compare(M.barLabel(null, 0), "");
    }

    function test_bar_label_single_entry_is_bare_countdown() {
        compare(M.barLabel([entry("a", 723000)], 0), "12:03");
    }

    function test_bar_label_fuses_count_when_more_than_one() {
        var list = [entry("a", 723000), entry("b", 800000), entry("c", 900000)];
        compare(M.barLabel(list, 0), "12:03 / 3");
    }

    function test_summary_lines() {
        compare(M.summaryLines([], 0).length, 0);
        compare(M.summaryLines([entry("a", 723000, "coffee")], 0).join("|"), "coffee / 12:03");
    }

    function test_due_clock_is_local_wall_clock() {
        // Built from the same Date rather than a literal: this runs under
        // whatever TZ the test host has.
        var when = new Date(2026, 7, 11, 14, 32, 0).getTime();
        var d = new Date(when);
        var expected = (d.getHours() < 10 ? "0" : "") + d.getHours() + ":"
            + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes();
        compare(M.dueClock(when), expected);
    }
}

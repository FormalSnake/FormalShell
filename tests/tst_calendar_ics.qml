import QtQuick
import QtTest
import "../shell/Calendar/ics.js" as Ics

TestCase {
    name: "CalendarIcs"

    function _local(y, m, d, h, mi) {
        return new Date(y, m, d, h || 0, mi || 0);
    }

    // unfold

    // Folding inserts CRLF + a single fold-marker whitespace character AT a
    // split point in the octet stream — it does not replace or add to
    // whatever whitespace the content already had. So a fold that lands
    // right after "about " (the space stays with the first line) reads back
    // correctly only once the single inserted marker after the CRLF is
    // stripped, leaving that original space in place.
    function test_unfold_joins_a_space_continuation_line() {
        var folded = "SUMMARY:Long meeting about \n roadmap planning";
        compare(Ics.unfold(folded), "SUMMARY:Long meeting about roadmap planning");
    }

    function test_unfold_joins_a_tab_continuation_line() {
        var folded = "SUMMARY:Long meeting\n\tcontinued";
        compare(Ics.unfold(folded), "SUMMARY:Long meetingcontinued");
    }

    function test_unfold_normalizes_crlf_first() {
        var folded = "SUMMARY:Foo \r\n bar";
        compare(Ics.unfold(folded), "SUMMARY:Foo bar");
    }

    // parseEvents — basic shape

    function test_parses_a_single_timed_event() {
        var ics = [
            "BEGIN:VCALENDAR",
            "BEGIN:VEVENT",
            "UID:abc-123",
            "SUMMARY:Team sync",
            "DTSTART:20260315T090000",
            "DTEND:20260315T100000",
            "END:VEVENT",
            "END:VCALENDAR"
        ].join("\n");
        var events = Ics.parseEvents(ics);
        compare(events.length, 1);
        compare(events[0].uid, "abc-123");
        compare(events[0].summary, "Team sync");
        compare(events[0].allDay, false);
        verify(events[0].start instanceof Date);
        compare(events[0].start.getFullYear(), 2026);
        compare(events[0].start.getMonth(), 2);
        compare(events[0].start.getDate(), 15);
        compare(events[0].start.getHours(), 9);
        verify(events[0].end instanceof Date);
        compare(events[0].end.getHours(), 10);
    }

    function test_parses_an_all_day_event() {
        var ics = [
            "BEGIN:VEVENT",
            "UID:day-1",
            "SUMMARY:Conference",
            "DTSTART;VALUE=DATE:20260701",
            "DTEND;VALUE=DATE:20260702",
            "END:VEVENT"
        ].join("\n");
        var events = Ics.parseEvents(ics);
        compare(events.length, 1);
        compare(events[0].allDay, true);
        compare(events[0].start.getFullYear(), 2026);
        compare(events[0].start.getMonth(), 6);
        compare(events[0].start.getDate(), 1);
    }

    function test_utc_dtstart_is_read_as_utc() {
        var ics = "BEGIN:VEVENT\nUID:u\nSUMMARY:S\nDTSTART:20260315T120000Z\nEND:VEVENT";
        var events = Ics.parseEvents(ics);
        compare(events.length, 1);
        compare(events[0].start.getTime(), Date.UTC(2026, 2, 15, 12, 0, 0));
    }

    function test_parses_multiple_vevents_across_concatenated_vcalendars() {
        var ics = [
            "BEGIN:VCALENDAR", "BEGIN:VEVENT", "UID:one", "SUMMARY:One", "DTSTART:20260101T000000", "END:VEVENT", "END:VCALENDAR",
            "BEGIN:VCALENDAR", "BEGIN:VEVENT", "UID:two", "SUMMARY:Two", "DTSTART:20260102T000000", "END:VEVENT", "END:VCALENDAR"
        ].join("\n");
        var events = Ics.parseEvents(ics);
        compare(events.length, 2);
        compare(events[0].uid, "one");
        compare(events[1].uid, "two");
    }

    function test_event_without_dtstart_is_skipped() {
        var ics = "BEGIN:VEVENT\nUID:no-start\nSUMMARY:No start\nEND:VEVENT";
        compare(Ics.parseEvents(ics).length, 0);
    }

    function test_summary_is_unescaped() {
        var ics = "BEGIN:VEVENT\nUID:esc\nSUMMARY:Foo\\, bar\\; baz\\nqux\nDTSTART:20260101T000000\nEND:VEVENT";
        var events = Ics.parseEvents(ics);
        compare(events[0].summary, "Foo, bar; baz\nqux");
    }

    function test_missing_summary_falls_back_to_untitled() {
        var ics = "BEGIN:VEVENT\nUID:u\nDTSTART:20260101T000000\nEND:VEVENT";
        compare(Ics.parseEvents(ics)[0].summary, "(untitled)");
    }

    function test_empty_text_yields_no_events() {
        compare(Ics.parseEvents("").length, 0);
    }

    function test_garbage_text_yields_no_events_not_a_crash() {
        compare(Ics.parseEvents("not an ics file at all\n\n\t\t").length, 0);
    }

    function test_folded_summary_line_is_reassembled_before_parsing() {
        var ics = "BEGIN:VEVENT\nUID:u\nSUMMARY:Long title that \n continues here\nDTSTART:20260101T000000\nEND:VEVENT";
        compare(Ics.parseEvents(ics)[0].summary, "Long title that continues here");
    }

    // eventsOnDate

    function test_events_on_date_matches_local_calendar_day() {
        var events = [
            { uid: "a", summary: "A", start: _local(2026, 2, 15, 9, 0), end: null, allDay: false },
            { uid: "b", summary: "B", start: _local(2026, 2, 16, 9, 0), end: null, allDay: false }
        ];
        var matches = Ics.eventsOnDate(events, _local(2026, 2, 15));
        compare(matches.length, 1);
        compare(matches[0].uid, "a");
    }

    function test_events_on_date_ignores_time_of_day() {
        var events = [{ uid: "a", summary: "A", start: _local(2026, 2, 15, 23, 45), end: null, allDay: false }];
        compare(Ics.eventsOnDate(events, _local(2026, 2, 15, 0, 1)).length, 1);
    }

    function test_events_on_date_returns_empty_for_no_match() {
        var events = [{ uid: "a", summary: "A", start: _local(2026, 2, 15), end: null, allDay: true }];
        compare(Ics.eventsOnDate(events, _local(2026, 2, 16)).length, 0);
    }

    // RRULE expansion — parseEvents takes an optional [windowStart, windowEnd]
    // (inclusive instants); recurring events expand to instances inside it,
    // non-recurring events ignore it entirely.

    function _rrIcs(dtstart, rrule, extra) {
        return "BEGIN:VEVENT\nUID:r\nSUMMARY:Rec\nDTSTART:" + dtstart + "\n" + rrule + "\n" + (extra ? extra + "\n" : "") + "END:VEVENT";
    }

    function test_daily_rrule_expands_into_window_instances() {
        var ics = "BEGIN:VEVENT\nUID:d\nSUMMARY:Standup\nDTSTART:20260301T090000\nDTEND:20260301T091500\nRRULE:FREQ=DAILY\nEND:VEVENT";
        var events = Ics.parseEvents(ics, _local(2026, 2, 1), _local(2026, 2, 5, 23, 59));
        compare(events.length, 5);
        for (var i = 0; i < 5; i++) {
            compare(events[i].start.getDate(), 1 + i);
            compare(events[i].start.getHours(), 9);
            compare(events[i].end.getMinutes(), 15);
        }
    }

    function test_expanded_instances_get_distinct_uids_derived_from_the_master() {
        var ics = "BEGIN:VEVENT\nUID:d\nSUMMARY:S\nDTSTART:20260301T090000\nRRULE:FREQ=DAILY;COUNT=2\nEND:VEVENT";
        var events = Ics.parseEvents(ics, _local(2026, 2, 1), _local(2026, 2, 31, 23, 59));
        compare(events.length, 2);
        verify(events[0].uid !== events[1].uid);
        compare(events[0].uid.indexOf("d#"), 0);
    }

    function test_daily_interval_two_skips_alternate_days() {
        var ics = _rrIcs("20260301T090000", "RRULE:FREQ=DAILY;INTERVAL=2");
        var events = Ics.parseEvents(ics, _local(2026, 2, 1), _local(2026, 2, 7, 23, 59));
        compare(events.length, 4);
        compare(events[0].start.getDate(), 1);
        compare(events[1].start.getDate(), 3);
        compare(events[2].start.getDate(), 5);
        compare(events[3].start.getDate(), 7);
    }

    function test_weekly_rrule_expands_on_the_dtstart_weekday() {
        // 2026-03-02 is a Monday.
        var ics = _rrIcs("20260302T100000", "RRULE:FREQ=WEEKLY");
        var events = Ics.parseEvents(ics, _local(2026, 2, 1), _local(2026, 2, 31, 23, 59));
        compare(events.length, 5);
        for (var i = 0; i < events.length; i++) {
            compare(events[i].start.getDay(), 1);
            compare(events[i].start.getDate(), 2 + 7 * i);
        }
    }

    function test_monthly_rrule_keeps_the_day_of_month() {
        var ics = _rrIcs("20260115T090000", "RRULE:FREQ=MONTHLY");
        var events = Ics.parseEvents(ics, _local(2026, 0, 1), _local(2026, 3, 30, 23, 59));
        compare(events.length, 4);
        for (var i = 0; i < events.length; i++) {
            compare(events[i].start.getDate(), 15);
            compare(events[i].start.getMonth(), i);
        }
    }

    function test_monthly_rrule_skips_months_without_the_day() {
        // Jan 31 monthly: Feb and Apr have no 31st — skipped, not shifted.
        var ics = _rrIcs("20260131T090000", "RRULE:FREQ=MONTHLY");
        var events = Ics.parseEvents(ics, _local(2026, 0, 1), _local(2026, 3, 30, 23, 59));
        compare(events.length, 2);
        compare(events[0].start.getMonth(), 0);
        compare(events[1].start.getMonth(), 2);
        compare(events[1].start.getDate(), 31);
    }

    function test_yearly_rrule_expands_across_years() {
        var ics = _rrIcs("20260704T120000", "RRULE:FREQ=YEARLY");
        var events = Ics.parseEvents(ics, _local(2026, 0, 1), _local(2028, 11, 31, 23, 59));
        compare(events.length, 3);
        for (var i = 0; i < events.length; i++) {
            compare(events[i].start.getFullYear(), 2026 + i);
            compare(events[i].start.getMonth(), 6);
            compare(events[i].start.getDate(), 4);
        }
    }

    function test_count_bounds_the_expansion() {
        var ics = _rrIcs("20260301T090000", "RRULE:FREQ=DAILY;COUNT=3");
        var events = Ics.parseEvents(ics, _local(2026, 2, 1), _local(2026, 2, 31, 23, 59));
        compare(events.length, 3);
        compare(events[2].start.getDate(), 3);
    }

    function test_count_is_consumed_by_occurrences_before_the_window() {
        var ics = _rrIcs("20260301T090000", "RRULE:FREQ=DAILY;COUNT=3");
        var events = Ics.parseEvents(ics, _local(2026, 2, 3), _local(2026, 2, 31, 23, 59));
        compare(events.length, 1);
        compare(events[0].start.getDate(), 3);
    }

    function test_until_bounds_the_expansion_inclusively() {
        var ics = _rrIcs("20260301T090000", "RRULE:FREQ=DAILY;UNTIL=20260303T090000");
        var events = Ics.parseEvents(ics, _local(2026, 2, 1), _local(2026, 2, 31, 23, 59));
        compare(events.length, 3);
        compare(events[2].start.getDate(), 3);
    }

    function test_weekly_byday_expands_on_each_listed_weekday() {
        // 2026-03-02 is a Monday; expect Mo/We instances: 2, 4, 9, 11.
        var ics = _rrIcs("20260302T090000", "RRULE:FREQ=WEEKLY;BYDAY=MO,WE");
        var events = Ics.parseEvents(ics, _local(2026, 2, 1), _local(2026, 2, 12, 23, 59));
        compare(events.length, 4);
        compare(events[0].start.getDate(), 2);
        compare(events[1].start.getDate(), 4);
        compare(events[2].start.getDate(), 9);
        compare(events[3].start.getDate(), 11);
        for (var i = 0; i < events.length; i++)
            verify(events[i].start.getDay() === 1 || events[i].start.getDay() === 3);
    }

    function test_unsupported_rrule_part_falls_back_to_the_single_anchor() {
        var ics = _rrIcs("20260301T090000", "RRULE:FREQ=MONTHLY;BYSETPOS=1");
        var events = Ics.parseEvents(ics, _local(2026, 2, 1), _local(2026, 11, 31, 23, 59));
        compare(events.length, 1);
        compare(events[0].uid, "r");
        compare(events[0].start.getDate(), 1);
    }

    function test_exdate_removes_the_matching_instance() {
        var ics = _rrIcs("20260301T090000", "RRULE:FREQ=DAILY;COUNT=3", "EXDATE:20260302T090000");
        var events = Ics.parseEvents(ics, _local(2026, 2, 1), _local(2026, 2, 31, 23, 59));
        compare(events.length, 2);
        compare(events[0].start.getDate(), 1);
        compare(events[1].start.getDate(), 3);
    }

    function test_non_recurring_events_ignore_the_window() {
        var ics = "BEGIN:VEVENT\nUID:far\nSUMMARY:S\nDTSTART:20270601T090000\nEND:VEVENT";
        var events = Ics.parseEvents(ics, _local(2026, 2, 1), _local(2026, 2, 31, 23, 59));
        compare(events.length, 1);
    }

    function _yyyymmdd(d) {
        var mm = ("0" + (d.getMonth() + 1)).slice(-2);
        var dd = ("0" + d.getDate()).slice(-2);
        return "" + d.getFullYear() + mm + dd;
    }

    function test_default_window_covers_today() {
        // The no-window call shape CalendarEventsService uses.
        var ics = "BEGIN:VEVENT\nUID:t\nSUMMARY:S\nDTSTART:" + _yyyymmdd(new Date()) + "T090000\nRRULE:FREQ=DAILY;COUNT=2\nEND:VEVENT";
        compare(Ics.parseEvents(ics).length, 2);
    }

    // mergeEvents

    function _event(uid, summary) {
        return { uid: uid, summary: summary, start: _local(2026, 2, 15), end: null, allDay: true };
    }

    function test_merge_concatenates_disjoint_uids_in_order() {
        var merged = Ics.mergeEvents([_event("a", "A")], [_event("b", "B"), _event("c", "C")]);
        compare(merged.length, 3);
        compare(merged[0].uid, "a");
        compare(merged[1].uid, "b");
        compare(merged[2].uid, "c");
    }

    function test_merge_dedupes_by_uid_with_primary_winning() {
        var merged = Ics.mergeEvents([_event("a", "ics copy")], [_event("a", "eds copy"), _event("b", "B")]);
        compare(merged.length, 2);
        compare(merged[0].summary, "ics copy");
        compare(merged[1].uid, "b");
    }

    function test_merge_dedupes_within_one_array_too() {
        var merged = Ics.mergeEvents([], [_event("a", "first"), _event("a", "second")]);
        compare(merged.length, 1);
        compare(merged[0].summary, "first");
    }

    function test_merge_keeps_every_event_with_an_empty_uid() {
        var merged = Ics.mergeEvents([_event("", "one")], [_event("", "two")]);
        compare(merged.length, 2);
    }

    function test_merge_of_two_empty_arrays_is_empty() {
        compare(Ics.mergeEvents([], []).length, 0);
    }
}

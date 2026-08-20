import QtQuick
import QtTest
import "../shell/Calendar/agenda.js" as Agenda

TestCase {
    name: "CalendarAgenda"

    // Local-time construction throughout: agenda.js reads local wall-clock
    // fields, the same single-timezone stance ics.js's own parser takes.
    function _at(y, m, d, h, mi) {
        return new Date(y, m, d, h || 0, mi || 0);
    }

    function _event(summary, start, end, allDay) {
        return { uid: summary, summary: summary, start: start, end: end || null, allDay: allDay === true };
    }

    function _summaries(events) {
        return events.map(function (e) { return e.summary; }).join(",");
    }

    // sortForDay

    function test_sort_puts_all_day_events_ahead_of_timed_ones() {
        var timed = _event("TIMED", _at(2026, 7, 20, 9, 0));
        var allDay = _event("ALLDAY", _at(2026, 7, 20), null, true);
        compare(_summaries(Agenda.sortForDay([timed, allDay])), "ALLDAY,TIMED");
    }

    function test_sort_orders_timed_events_chronologically() {
        var late = _event("LATE", _at(2026, 7, 20, 17, 30));
        var early = _event("EARLY", _at(2026, 7, 20, 8, 15));
        var noon = _event("NOON", _at(2026, 7, 20, 12, 0));
        compare(_summaries(Agenda.sortForDay([late, early, noon])), "EARLY,NOON,LATE");
    }

    function test_sort_breaks_a_same_minute_tie_on_summary() {
        var b = _event("B", _at(2026, 7, 20, 9, 0));
        var a = _event("A", _at(2026, 7, 20, 9, 0));
        compare(_summaries(Agenda.sortForDay([b, a])), "A,B");
    }

    function test_sort_leaves_the_caller_array_untouched() {
        var input = [_event("LATE", _at(2026, 7, 20, 17, 0)), _event("EARLY", _at(2026, 7, 20, 8, 0))];
        Agenda.sortForDay(input);
        compare(_summaries(input), "LATE,EARLY");
    }

    // clockTime

    function test_clock_time_writes_24_hour_by_default() {
        compare(Agenda.clockTime(_at(2026, 7, 20, 9, 5), false), "09:05");
        compare(Agenda.clockTime(_at(2026, 7, 20, 21, 30), false), "21:30");
    }

    function test_clock_time_writes_meridiem_when_asked() {
        compare(Agenda.clockTime(_at(2026, 7, 20, 9, 5), true), "9:05 AM");
        compare(Agenda.clockTime(_at(2026, 7, 20, 21, 30), true), "9:30 PM");
    }

    function test_clock_time_writes_midnight_and_noon_as_12() {
        compare(Agenda.clockTime(_at(2026, 7, 20, 0, 0), true), "12:00 AM");
        compare(Agenda.clockTime(_at(2026, 7, 20, 12, 0), true), "12:00 PM");
    }

    // timeLabel

    function test_time_label_of_an_all_day_event() {
        compare(Agenda.timeLabel(_event("X", _at(2026, 7, 20), null, true), false), "ALL DAY");
    }

    function test_time_label_counts_a_multi_day_all_day_span_from_an_exclusive_end() {
        // DTEND is non-inclusive for VALUE=DATE: Aug 20 -> Aug 23 covers
        // three days, so the tail reads +2D.
        var e = _event("X", _at(2026, 7, 20), _at(2026, 7, 23), true);
        compare(Agenda.timeLabel(e, false), "ALL DAY +2D");
    }

    function test_time_label_of_an_event_with_no_end_is_the_start_alone() {
        compare(Agenda.timeLabel(_event("X", _at(2026, 7, 20, 9, 0)), false), "09:00");
    }

    function test_time_label_of_a_zero_length_event_is_the_start_alone() {
        var e = _event("X", _at(2026, 7, 20, 9, 0), _at(2026, 7, 20, 9, 0));
        compare(Agenda.timeLabel(e, false), "09:00");
    }

    function test_time_label_of_a_timed_range() {
        var e = _event("X", _at(2026, 7, 20, 9, 0), _at(2026, 7, 20, 10, 30));
        compare(Agenda.timeLabel(e, false), "09:00-10:30");
    }

    function test_time_label_tails_a_range_that_ends_on_a_later_day() {
        var e = _event("X", _at(2026, 7, 20, 22, 0), _at(2026, 7, 21, 1, 30));
        compare(Agenda.timeLabel(e, false), "22:00-01:30 +1D");
    }

    function test_time_label_prints_one_meridiem_for_a_range_inside_one_half_day() {
        var e = _event("X", _at(2026, 7, 20, 9, 0), _at(2026, 7, 20, 10, 30));
        compare(Agenda.timeLabel(e, true), "9:00-10:30 AM");
    }

    function test_time_label_prints_both_meridiems_across_noon() {
        var e = _event("X", _at(2026, 7, 20, 9, 0), _at(2026, 7, 20, 13, 30));
        compare(Agenda.timeLabel(e, true), "9:00 AM-1:30 PM");
    }

    // status

    function test_status_of_an_all_day_event_is_never_running() {
        var e = _event("X", _at(2026, 7, 20), _at(2026, 7, 21), true);
        compare(Agenda.status(e, _at(2026, 7, 20, 12, 0)), "allday");
    }

    function test_status_before_the_start_is_upcoming() {
        var e = _event("X", _at(2026, 7, 20, 14, 0), _at(2026, 7, 20, 15, 0));
        compare(Agenda.status(e, _at(2026, 7, 20, 13, 59)), "upcoming");
    }

    function test_status_inside_the_range_is_now() {
        var e = _event("X", _at(2026, 7, 20, 14, 0), _at(2026, 7, 20, 15, 0));
        compare(Agenda.status(e, _at(2026, 7, 20, 14, 0)), "now");
        compare(Agenda.status(e, _at(2026, 7, 20, 14, 59)), "now");
    }

    function test_status_at_the_end_instant_is_already_past() {
        var e = _event("X", _at(2026, 7, 20, 14, 0), _at(2026, 7, 20, 15, 0));
        compare(Agenda.status(e, _at(2026, 7, 20, 15, 0)), "past");
    }

    function test_status_of_an_endless_event_is_past_once_it_starts() {
        var e = _event("X", _at(2026, 7, 20, 14, 0));
        compare(Agenda.status(e, _at(2026, 7, 20, 14, 1)), "past");
    }

    // hasRunning / nextUp

    function test_has_running_finds_the_event_in_progress() {
        var events = [
            _event("DONE", _at(2026, 7, 20, 9, 0), _at(2026, 7, 20, 10, 0)),
            _event("LIVE", _at(2026, 7, 20, 14, 0), _at(2026, 7, 20, 15, 0))
        ];
        verify(Agenda.hasRunning(events, _at(2026, 7, 20, 14, 30)));
        verify(!Agenda.hasRunning(events, _at(2026, 7, 20, 16, 0)));
    }

    function test_next_up_is_the_earliest_event_still_to_start() {
        var events = [
            _event("EVENING", _at(2026, 7, 20, 19, 0)),
            _event("DONE", _at(2026, 7, 20, 9, 0), _at(2026, 7, 20, 10, 0)),
            _event("AFTERNOON", _at(2026, 7, 20, 15, 0))
        ];
        compare(Agenda.nextUp(events, _at(2026, 7, 20, 12, 0)).summary, "AFTERNOON");
    }

    function test_next_up_is_null_once_the_day_is_spent() {
        var events = [_event("DONE", _at(2026, 7, 20, 9, 0), _at(2026, 7, 20, 10, 0))];
        compare(Agenda.nextUp(events, _at(2026, 7, 20, 23, 0)), null);
    }

    function test_next_up_ignores_all_day_events() {
        var events = [_event("ALLDAY", _at(2026, 7, 20), null, true)];
        compare(Agenda.nextUp(events, _at(2026, 7, 20, 8, 0)), null);
    }

    // widestLabel

    function test_widest_label_is_the_longest_the_day_prints() {
        var events = [
            _event("A", _at(2026, 7, 20, 9, 0)),
            _event("B", _at(2026, 7, 20, 14, 0), _at(2026, 7, 20, 15, 30))
        ];
        compare(Agenda.widestLabel(events, false), "14:00-15:30");
    }

    function test_widest_label_of_an_empty_day_is_empty() {
        compare(Agenda.widestLabel([], false), "");
    }
}

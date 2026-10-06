use chrono::{DateTime, Datelike, Local, NaiveDate, TimeZone, Timelike, Utc, Weekday};
use fs_info::calendar::ics::*;

fn local(y: i32, m: u32, d: u32, h: u32, mi: u32) -> DateTime<Local> {
    Local.with_ymd_and_hms(y, m, d, h, mi, 0).unwrap()
}

fn day(y: i32, m: u32, d: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(y, m, d).unwrap()
}

type Window = (DateTime<Local>, DateTime<Local>);

fn window(from: DateTime<Local>, to: DateTime<Local>) -> Window {
    (from, to)
}

fn end_of(y: i32, m: u32, d: u32) -> DateTime<Local> {
    local(y, m, d, 23, 59)
}

/// A window wide enough that it never decides a non-recurring test.
fn default_win() -> Window {
    default_window(Local::now())
}

// Months in these tests are 1-based (the QML cases were 0-based).

// Folding inserts CRLF + a single fold-marker whitespace character AT a split
// point in the octet stream: it does not replace or add to whatever
// whitespace the content already had. So a fold that lands right after
// "about " (the space stays with the first line) reads back correctly only
// once the single inserted marker after the CRLF is stripped, leaving that
// original space in place.
#[test]
fn unfold_joins_a_space_continuation_line() {
    let folded = "SUMMARY:Long meeting about \n roadmap planning";
    assert_eq!(unfold(folded), "SUMMARY:Long meeting about roadmap planning");
}

#[test]
fn unfold_joins_a_tab_continuation_line() {
    assert_eq!(unfold("SUMMARY:Long meeting\n\tcontinued"), "SUMMARY:Long meetingcontinued");
}

#[test]
fn unfold_normalizes_crlf_first() {
    assert_eq!(unfold("SUMMARY:Foo \r\n bar"), "SUMMARY:Foo bar");
}

#[test]
fn parses_a_single_timed_event() {
    let ics = [
        "BEGIN:VCALENDAR",
        "BEGIN:VEVENT",
        "UID:abc-123",
        "SUMMARY:Team sync",
        "DTSTART:20260315T090000",
        "DTEND:20260315T100000",
        "END:VEVENT",
        "END:VCALENDAR",
    ]
    .join("\n");
    let events = parse_events(&ics, default_win());
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].uid, "abc-123");
    assert_eq!(events[0].summary, "Team sync");
    assert!(!events[0].all_day);
    assert_eq!(events[0].start.year(), 2026);
    assert_eq!(events[0].start.month(), 3);
    assert_eq!(events[0].start.day(), 15);
    assert_eq!(events[0].start.hour(), 9);
    assert_eq!(events[0].end.unwrap().hour(), 10);
}

#[test]
fn parses_an_all_day_event() {
    let ics = [
        "BEGIN:VEVENT",
        "UID:day-1",
        "SUMMARY:Conference",
        "DTSTART;VALUE=DATE:20260701",
        "DTEND;VALUE=DATE:20260702",
        "END:VEVENT",
    ]
    .join("\n");
    let events = parse_events(&ics, default_win());
    assert_eq!(events.len(), 1);
    assert!(events[0].all_day);
    assert_eq!(events[0].start.year(), 2026);
    assert_eq!(events[0].start.month(), 7);
    assert_eq!(events[0].start.day(), 1);
}

#[test]
fn utc_dtstart_is_read_as_utc() {
    let ics = "BEGIN:VEVENT\nUID:u\nSUMMARY:S\nDTSTART:20260315T120000Z\nEND:VEVENT";
    let events = parse_events(ics, default_win());
    assert_eq!(events.len(), 1);
    assert_eq!(
        events[0].start.timestamp_millis(),
        Utc.with_ymd_and_hms(2026, 3, 15, 12, 0, 0).unwrap().timestamp_millis()
    );
}

#[test]
fn parses_multiple_vevents_across_concatenated_vcalendars() {
    let ics = [
        "BEGIN:VCALENDAR", "BEGIN:VEVENT", "UID:one", "SUMMARY:One", "DTSTART:20260101T000000", "END:VEVENT", "END:VCALENDAR",
        "BEGIN:VCALENDAR", "BEGIN:VEVENT", "UID:two", "SUMMARY:Two", "DTSTART:20260102T000000", "END:VEVENT", "END:VCALENDAR",
    ]
    .join("\n");
    let events = parse_events(&ics, default_win());
    assert_eq!(events.len(), 2);
    assert_eq!(events[0].uid, "one");
    assert_eq!(events[1].uid, "two");
}

#[test]
fn event_without_dtstart_is_skipped() {
    let ics = "BEGIN:VEVENT\nUID:no-start\nSUMMARY:No start\nEND:VEVENT";
    assert_eq!(parse_events(ics, default_win()).len(), 0);
}

#[test]
fn summary_is_unescaped() {
    let ics = "BEGIN:VEVENT\nUID:esc\nSUMMARY:Foo\\, bar\\; baz\\nqux\nDTSTART:20260101T000000\nEND:VEVENT";
    let events = parse_events(ics, default_win());
    assert_eq!(events[0].summary, "Foo, bar; baz\nqux");
}

#[test]
fn missing_summary_falls_back_to_untitled() {
    let ics = "BEGIN:VEVENT\nUID:u\nDTSTART:20260101T000000\nEND:VEVENT";
    assert_eq!(parse_events(ics, default_win())[0].summary, "(untitled)");
}

#[test]
fn empty_text_yields_no_events() {
    assert_eq!(parse_events("", default_win()).len(), 0);
}

#[test]
fn garbage_text_yields_no_events_not_a_crash() {
    assert_eq!(parse_events("not an ics file at all\n\n\t\t", default_win()).len(), 0);
}

#[test]
fn folded_summary_line_is_reassembled_before_parsing() {
    let ics = "BEGIN:VEVENT\nUID:u\nSUMMARY:Long title that \n continues here\nDTSTART:20260101T000000\nEND:VEVENT";
    assert_eq!(parse_events(ics, default_win())[0].summary, "Long title that continues here");
}

fn plain(uid: &str, summary: &str, start: DateTime<Local>, all_day: bool) -> Event {
    Event { uid: uid.into(), summary: summary.into(), start, end: None, all_day }
}

#[test]
fn events_on_date_matches_local_calendar_day() {
    let events = [
        plain("a", "A", local(2026, 3, 15, 9, 0), false),
        plain("b", "B", local(2026, 3, 16, 9, 0), false),
    ];
    let matches = events_on_date(&events, day(2026, 3, 15));
    assert_eq!(matches.len(), 1);
    assert_eq!(matches[0].uid, "a");
}

#[test]
fn events_on_date_ignores_time_of_day() {
    let events = [plain("a", "A", local(2026, 3, 15, 23, 45), false)];
    assert_eq!(events_on_date(&events, day(2026, 3, 15)).len(), 1);
}

#[test]
fn events_on_date_returns_empty_for_no_match() {
    let events = [plain("a", "A", local(2026, 3, 15, 0, 0), true)];
    assert_eq!(events_on_date(&events, day(2026, 3, 16)).len(), 0);
}

// RRULE expansion: parse_events takes a [start, end] window (inclusive
// instants); recurring events expand to instances inside it, non-recurring
// events ignore it entirely.

fn rr_ics(dtstart: &str, rrule: &str, extra: Option<&str>) -> String {
    format!(
        "BEGIN:VEVENT\nUID:r\nSUMMARY:Rec\nDTSTART:{dtstart}\n{rrule}\n{}END:VEVENT",
        extra.map_or(String::new(), |e| format!("{e}\n"))
    )
}

#[test]
fn daily_rrule_expands_into_window_instances() {
    let ics = "BEGIN:VEVENT\nUID:d\nSUMMARY:Standup\nDTSTART:20260301T090000\nDTEND:20260301T091500\nRRULE:FREQ=DAILY\nEND:VEVENT";
    let events = parse_events(ics, window(local(2026, 3, 1, 0, 0), end_of(2026, 3, 5)));
    assert_eq!(events.len(), 5);
    for (i, e) in events.iter().enumerate() {
        assert_eq!(e.start.day(), 1 + i as u32);
        assert_eq!(e.start.hour(), 9);
        assert_eq!(e.end.unwrap().minute(), 15);
    }
}

#[test]
fn expanded_instances_get_distinct_uids_derived_from_the_master() {
    let ics = "BEGIN:VEVENT\nUID:d\nSUMMARY:S\nDTSTART:20260301T090000\nRRULE:FREQ=DAILY;COUNT=2\nEND:VEVENT";
    let events = parse_events(ics, window(local(2026, 3, 1, 0, 0), end_of(2026, 3, 31)));
    assert_eq!(events.len(), 2);
    assert_ne!(events[0].uid, events[1].uid);
    assert!(events[0].uid.starts_with("d#"));
    assert_eq!(events[0].uid, "d#20260301T090000");
}

#[test]
fn daily_interval_two_skips_alternate_days() {
    let ics = rr_ics("20260301T090000", "RRULE:FREQ=DAILY;INTERVAL=2", None);
    let events = parse_events(&ics, window(local(2026, 3, 1, 0, 0), end_of(2026, 3, 7)));
    let days: Vec<u32> = events.iter().map(|e| e.start.day()).collect();
    assert_eq!(days, [1, 3, 5, 7]);
}

#[test]
fn weekly_rrule_expands_on_the_dtstart_weekday() {
    // 2026-03-02 is a Monday.
    let ics = rr_ics("20260302T100000", "RRULE:FREQ=WEEKLY", None);
    let events = parse_events(&ics, window(local(2026, 3, 1, 0, 0), end_of(2026, 3, 31)));
    assert_eq!(events.len(), 5);
    for (i, e) in events.iter().enumerate() {
        assert_eq!(e.start.weekday(), Weekday::Mon);
        assert_eq!(e.start.day(), 2 + 7 * i as u32);
    }
}

#[test]
fn monthly_rrule_keeps_the_day_of_month() {
    let ics = rr_ics("20260115T090000", "RRULE:FREQ=MONTHLY", None);
    let events = parse_events(&ics, window(local(2026, 1, 1, 0, 0), end_of(2026, 4, 30)));
    assert_eq!(events.len(), 4);
    for (i, e) in events.iter().enumerate() {
        assert_eq!(e.start.day(), 15);
        assert_eq!(e.start.month(), 1 + i as u32);
    }
}

#[test]
fn monthly_rrule_skips_months_without_the_day() {
    // Jan 31 monthly: Feb and Apr have no 31st, skipped, not shifted.
    let ics = rr_ics("20260131T090000", "RRULE:FREQ=MONTHLY", None);
    let events = parse_events(&ics, window(local(2026, 1, 1, 0, 0), end_of(2026, 4, 30)));
    assert_eq!(events.len(), 2);
    assert_eq!(events[0].start.month(), 1);
    assert_eq!(events[1].start.month(), 3);
    assert_eq!(events[1].start.day(), 31);
}

#[test]
fn yearly_rrule_expands_across_years() {
    let ics = rr_ics("20260704T120000", "RRULE:FREQ=YEARLY", None);
    let events = parse_events(&ics, window(local(2026, 1, 1, 0, 0), end_of(2028, 12, 31)));
    assert_eq!(events.len(), 3);
    for (i, e) in events.iter().enumerate() {
        assert_eq!(e.start.year(), 2026 + i as i32);
        assert_eq!(e.start.month(), 7);
        assert_eq!(e.start.day(), 4);
    }
}

#[test]
fn count_bounds_the_expansion() {
    let ics = rr_ics("20260301T090000", "RRULE:FREQ=DAILY;COUNT=3", None);
    let events = parse_events(&ics, window(local(2026, 3, 1, 0, 0), end_of(2026, 3, 31)));
    assert_eq!(events.len(), 3);
    assert_eq!(events[2].start.day(), 3);
}

#[test]
fn count_is_consumed_by_occurrences_before_the_window() {
    let ics = rr_ics("20260301T090000", "RRULE:FREQ=DAILY;COUNT=3", None);
    let events = parse_events(&ics, window(local(2026, 3, 3, 0, 0), end_of(2026, 3, 31)));
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].start.day(), 3);
}

#[test]
fn until_bounds_the_expansion_inclusively() {
    let ics = rr_ics("20260301T090000", "RRULE:FREQ=DAILY;UNTIL=20260303T090000", None);
    let events = parse_events(&ics, window(local(2026, 3, 1, 0, 0), end_of(2026, 3, 31)));
    assert_eq!(events.len(), 3);
    assert_eq!(events[2].start.day(), 3);
}

#[test]
fn weekly_byday_expands_on_each_listed_weekday() {
    // 2026-03-02 is a Monday; expect Mo/We instances: 2, 4, 9, 11.
    let ics = rr_ics("20260302T090000", "RRULE:FREQ=WEEKLY;BYDAY=MO,WE", None);
    let events = parse_events(&ics, window(local(2026, 3, 1, 0, 0), end_of(2026, 3, 12)));
    let days: Vec<u32> = events.iter().map(|e| e.start.day()).collect();
    assert_eq!(days, [2, 4, 9, 11]);
    for e in &events {
        assert!(matches!(e.start.weekday(), Weekday::Mon | Weekday::Wed));
    }
}

#[test]
fn unsupported_rrule_part_falls_back_to_the_single_anchor() {
    let ics = rr_ics("20260301T090000", "RRULE:FREQ=MONTHLY;BYSETPOS=1", None);
    let events = parse_events(&ics, window(local(2026, 3, 1, 0, 0), end_of(2026, 12, 31)));
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].uid, "r");
    assert_eq!(events[0].start.day(), 1);
}

#[test]
fn exdate_removes_the_matching_instance() {
    let ics = rr_ics("20260301T090000", "RRULE:FREQ=DAILY;COUNT=3", Some("EXDATE:20260302T090000"));
    let events = parse_events(&ics, window(local(2026, 3, 1, 0, 0), end_of(2026, 3, 31)));
    assert_eq!(events.len(), 2);
    assert_eq!(events[0].start.day(), 1);
    assert_eq!(events[1].start.day(), 3);
}

#[test]
fn non_recurring_events_ignore_the_window() {
    let ics = "BEGIN:VEVENT\nUID:far\nSUMMARY:S\nDTSTART:20270601T090000\nEND:VEVENT";
    let events = parse_events(ics, window(local(2026, 3, 1, 0, 0), end_of(2026, 3, 31)));
    assert_eq!(events.len(), 1);
}

#[test]
fn default_window_covers_today() {
    // The no-window call shape CalendarEventsService uses.
    let today = Local::now().date_naive();
    let ics = format!(
        "BEGIN:VEVENT\nUID:t\nSUMMARY:S\nDTSTART:{}T090000\nRRULE:FREQ=DAILY;COUNT=2\nEND:VEVENT",
        today.format("%Y%m%d")
    );
    assert_eq!(parse_events(&ics, default_window(Local::now())).len(), 2);
}

fn keyed(uid: &str, summary: &str) -> Event {
    plain(uid, summary, local(2026, 3, 15, 0, 0), true)
}

#[test]
fn merge_concatenates_disjoint_uids_in_order() {
    let merged = merge_events(&[keyed("a", "A")], &[keyed("b", "B"), keyed("c", "C")]);
    let uids: Vec<&str> = merged.iter().map(|e| e.uid.as_str()).collect();
    assert_eq!(uids, ["a", "b", "c"]);
}

#[test]
fn merge_dedupes_by_uid_with_primary_winning() {
    let merged = merge_events(
        &[keyed("a", "ics copy")],
        &[keyed("a", "eds copy"), keyed("b", "B")],
    );
    assert_eq!(merged.len(), 2);
    assert_eq!(merged[0].summary, "ics copy");
    assert_eq!(merged[1].uid, "b");
}

#[test]
fn merge_dedupes_within_one_array_too() {
    let merged = merge_events(&[], &[keyed("a", "first"), keyed("a", "second")]);
    assert_eq!(merged.len(), 1);
    assert_eq!(merged[0].summary, "first");
}

#[test]
fn merge_keeps_every_event_with_an_empty_uid() {
    let merged = merge_events(&[keyed("", "one")], &[keyed("", "two")]);
    assert_eq!(merged.len(), 2);
}

#[test]
fn merge_of_two_empty_arrays_is_empty() {
    assert_eq!(merge_events(&[], &[]).len(), 0);
}

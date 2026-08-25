import QtQuick
import QtTest
import "../shell/Calendar/grid.js" as Grid

// Calendar/grid.js (M42 Task 2): the month grid CalendarPanel renders and
// the keyboard cursor addresses. Pure, so the 42-cell shape, the ISO week
// column, index-to-date and the event dot are all asserted head-on rather
// than inferred from a screenshot.
TestCase {
    name: "CalendarGrid"

    function test_a_month_is_always_six_weeks_of_seven_days() {
        compare(Grid.COLUMNS, 7);
        compare(Grid.monthCells(2026, 7).length, 42);
        // February in a non-leap year pads out to the same 42 cells, so
        // stepping months never resizes the card.
        compare(Grid.monthCells(2026, 1).length, 42);
    }

    function test_the_grid_starts_on_the_monday_of_the_first_week() {
        // 2026-08-01 is a Saturday, so the grid opens on Monday 2026-07-27.
        var cells = Grid.monthCells(2026, 7);
        compare(cells[0].year, 2026);
        compare(cells[0].month, 6);
        compare(cells[0].day, 27);
        compare(cells[0].inMonth, false);
    }

    function test_a_month_starting_on_monday_needs_no_leading_padding() {
        // 2026-06-01 is a Monday.
        var cells = Grid.monthCells(2026, 5);
        compare(cells[0].day, 1);
        compare(cells[0].month, 5);
        compare(cells[0].inMonth, true);
    }

    function test_in_month_marks_exactly_the_month_asked_for() {
        var cells = Grid.monthCells(2026, 7);
        var inMonth = cells.filter(function (c) { return c.inMonth; });
        compare(inMonth.length, 31);
        compare(inMonth[0].day, 1);
        compare(inMonth[30].day, 31);
    }

    function test_week_numbers_are_one_per_row_read_off_the_thursday() {
        var cells = Grid.monthCells(2026, 7);
        var weeks = Grid.weekNumbers(cells);
        compare(weeks.length, Grid.ROWS);
        // The row starting Monday 2026-07-27 has Thursday 2026-07-30 in it,
        // which is ISO week 31.
        compare(weeks[0], 31);
        compare(weeks[1], 32);
    }

    function test_week_numbers_cross_a_year_boundary_on_the_thursday() {
        // December 2026 runs into ISO week 53 of 2026 and then week 1.
        var weeks = Grid.weekNumbers(Grid.monthCells(2026, 11));
        compare(weeks[weeks.length - 1], 1);
    }

    function test_index_of_date_finds_the_cell_showing_that_day() {
        var cells = Grid.monthCells(2026, 7);
        var index = Grid.indexOfDate(cells, new Date(2026, 7, 1));
        compare(index, 5);
        compare(cells[index].day, 1);
    }

    function test_index_of_date_falls_back_to_the_first_day_of_the_month() {
        var cells = Grid.monthCells(2026, 7);
        // A date the grid isn't showing at all still yields a real position,
        // so the reveal-only first keypress has somewhere to appear.
        var index = Grid.indexOfDate(cells, new Date(2027, 2, 14));
        compare(index, 5);
        compare(cells[index].inMonth, true);
    }

    function test_date_at_reads_the_cell_back_as_a_date() {
        var cells = Grid.monthCells(2026, 7);
        var d = Grid.dateAt(cells, 5);
        compare(d.getFullYear(), 2026);
        compare(d.getMonth(), 7);
        compare(d.getDate(), 1);
        compare(Grid.dateAt(cells, -1), null);
        compare(Grid.dateAt(cells, 42), null);
    }

    function test_same_date_ignores_the_time_of_day() {
        var morning = new Date(2026, 7, 25, 9, 15);
        var evening = new Date(2026, 7, 25, 23, 45);
        compare(Grid.sameDate(morning, evening), true);
        compare(Grid.sameDate(morning, new Date(2026, 7, 26)), false);
    }

    function test_the_event_dot_is_in_month_days_with_events_only() {
        var cells = Grid.monthCells(2026, 7);
        compare(Grid.showsEventDot(cells[5], 1), true);
        compare(Grid.showsEventDot(cells[5], 0), false);
        // A padding day belongs to the adjacent month and is dimmed rather
        // than dotted, however many events it has.
        compare(Grid.showsEventDot(cells[0], 3), false);
        compare(Grid.showsEventDot(null, 3), false);
    }

    function test_step_month_carries_the_year_across_january_and_december() {
        compare(Grid.stepMonth(2026, 11, 1).year, 2027);
        compare(Grid.stepMonth(2026, 11, 1).month, 0);
        compare(Grid.stepMonth(2026, 0, -1).year, 2025);
        compare(Grid.stepMonth(2026, 0, -1).month, 11);
    }

    function test_iso_date_pads_both_components() {
        compare(Grid.isoDate(new Date(2026, 0, 5)), "2026-01-05");
        compare(Grid.isoDate(new Date(2026, 11, 31)), "2026-12-31");
    }

    function test_parse_iso_date_accepts_only_a_real_calendar_day() {
        var d = Grid.parseIsoDate("2026-08-25");
        compare(d.getFullYear(), 2026);
        compare(d.getMonth(), 7);
        compare(d.getDate(), 25);
        // A day that rolls over is rejected rather than silently becoming
        // the next month.
        compare(Grid.parseIsoDate("2026-02-31"), null);
        compare(Grid.parseIsoDate("25/08/2026"), null);
        compare(Grid.parseIsoDate(""), null);
    }
}

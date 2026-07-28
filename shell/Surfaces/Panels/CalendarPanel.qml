import QtQuick
import qs.Core
import qs.Components
import "../../Calendar/progress.js" as Progress

// Month grid + year-progress popout (DESIGN.md §Panels' clock/calendar
// entry, spec §2, M6 Task 3): a MONTH/YEAR meta row, then the grid itself —
// weekday header meta row followed by one ledger cell per day, today
// selected (Cell's own inversion), days outside the current month dimmed to
// foregroundDim — and below it the year-progress bar as a full-width flat
// accent-fill cell with its percentage as mono text, mirroring AudioPanel's
// slider idiom. Modeled on Omarchy quattro's calendar widget (read only,
// not copied — CLAUDE.md's read-reference rule for that repo). The
// life-progress easter egg (double-click, birth year / life expectancy
// prompt via the menu's input mode) is M6 Task 4; this task only wires the
// always-available year fraction.
Panel {
    id: root

    panelTitle: "CALENDAR"
    panelWidth: 280

    readonly property var _monthNames: [
        "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
        "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"
    ]
    readonly property var _weekdayLabels: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

    // "Today" is frozen at whatever it was when last computed — refreshed on
    // open (in case the panel sat instantiated-but-closed across midnight)
    // and every minute while it stays open.
    property date _today: new Date()
    onIsOpenChanged: if (root.isOpen) root._today = new Date()

    Timer {
        interval: 60000
        running: root.isOpen
        repeat: true
        onTriggered: root._today = new Date()
    }

    readonly property int _year: root._today.getFullYear()
    readonly property int _month: root._today.getMonth()
    readonly property real _yearFraction: Progress.yearFraction(root._today)

    function _daysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate();
    }

    // Monday-first grid, padded with dimmed leading/trailing days from the
    // adjacent months so every row has exactly 7 cells.
    readonly property var _cells: {
        var year = root._year;
        var month = root._month;
        var firstWeekday = (new Date(year, month, 1).getDay() + 6) % 7;
        var daysInMonth = root._daysInMonth(year, month);
        var prevMonth = month === 0 ? 11 : month - 1;
        var prevYear = month === 0 ? year - 1 : year;
        var prevMonthDays = root._daysInMonth(prevYear, prevMonth);
        var today = root._today.getDate();

        var cells = [];
        for (var i = 0; i < firstWeekday; i++)
            cells.push({ day: prevMonthDays - firstWeekday + 1 + i, inMonth: false, isToday: false });
        for (var d = 1; d <= daysInMonth; d++)
            cells.push({ day: d, inMonth: true, isToday: d === today });
        var trailing = (7 - (cells.length % 7)) % 7;
        for (var t = 1; t <= trailing; t++)
            cells.push({ day: t, inMonth: false, isToday: false });
        return cells;
    }

    Cell {
        width: parent.width

        MetaLabel {
            text: root._monthNames[root._month] + " " + root._year
        }
    }

    Grid {
        id: dayGrid
        width: parent.width
        columns: 7

        Repeater {
            model: root._weekdayLabels

            delegate: Cell {
                id: weekdayCell
                required property string modelData
                width: dayGrid.width / 7

                MetaLabel {
                    anchors.centerIn: parent
                    text: weekdayCell.modelData
                }
            }
        }

        Repeater {
            model: root._cells

            delegate: Cell {
                id: dayCell
                required property var modelData
                width: dayGrid.width / 7
                selected: dayCell.modelData.isToday

                Text {
                    anchors.centerIn: parent
                    text: dayCell.modelData.day
                    color: dayCell.modelData.inMonth ? dayCell.foreground : Theme.color.foregroundDim
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.body
                }
            }
        }
    }

    Cell {
        id: yearCell
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.spacing.xs

            MetaLabel {
                text: "YEAR"
            }

            Text {
                text: Progress.formatPercent(root._yearFraction)
                color: yearCell.foreground
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
            }

            // Flat accent fill, no thumb, no radius — same idiom as
            // AudioPanel's volume slider, read-only here.
            Rectangle {
                width: parent.width
                height: 6
                color: Theme.color.rule

                Rectangle {
                    width: parent.width * root._yearFraction
                    height: parent.height
                    color: Theme.color.accent
                }
            }
        }
    }
}

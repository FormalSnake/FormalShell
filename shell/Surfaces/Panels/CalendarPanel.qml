import QtQuick
// Aliased, not a bare `import qs.Core`: QtQuick already exports a type
// named State (for property-binding states), and an unqualified import
// loses that name collision — State.wallpaper (here, calendarBirthYear)
// reads back undefined at runtime instead of hitting the qs.Core singleton
// (verified with a throwaway probe script, same failure ThemeEngine.qml's
// own header comment documents). Core.State/Core.Config/Core.Theme
// disambiguate it; importing qs.Core a second time unqualified alongside
// this one breaks qmllint's module resolution entirely, so every reference
// in this file goes through the Core. prefix, not just the new ones.
import qs.Core as Core
import qs.Components
import qs.Services
import "../../Calendar/progress.js" as Progress

// Month grid + year-progress popout (DESIGN.md §Panels' clock/calendar
// entry, spec §2, M6 Task 3): a MONTH/YEAR meta row, then the grid itself —
// weekday header meta row followed by one ledger cell per day, today
// selected (Cell's own inversion), days outside the current month dimmed to
// foregroundDim — and below it the year-progress bar as a full-width flat
// accent-fill cell with its percentage as mono text, mirroring AudioPanel's
// slider idiom. Modeled on Omarchy quattro's calendar widget (read only,
// not copied — CLAUDE.md's read-reference rule for that repo). The
// life-progress easter egg (M6 Task 4): double-clicking the year-progress
// bar prompts, through the menu's existing "input" mode, first for birth
// year then life expectancy; both persist to state.json via
// State.setCalendarLifeProgress(), mirroring wallpaper/mode/dnd's own alias
// + writeAdapter pattern. settings.json's calendar.birthYear/
// calendar.lifeExpectancy declaratively override the persisted state
// values when present (Progress.resolveOverride: settings wins, state is
// the fallback). Once both resolve to a valid pair the bar defaults to
// showing % of life lived instead of % of year elapsed; a further
// double-click toggles back to year progress. Events (M6 Task 5): a small
// accent dot under any in-month day that has one, sourced from
// CalendarEventsService's local .ics reader (docs/spikes/2026-07-28-eds-
// calendar-events.md records why EDS/GOA over D-Bus lost to that fallback);
// a TODAY ledger section below the grid lists today's events by summary, or
// a single dim "NO EVENTS" row when there are none — the honest-empty-state
// every other panel backend already follows in the test VM.
Panel {
    id: root

    panelTitle: "CALENDAR"
    panelWidth: 280

    // Set from shell.qml, the single Menu instance, needed to drive the
    // life-progress easter egg's two-step birth-year/life-expectancy prompt
    // through the menu's own input mode (M6 Task 4).
    property var menu: null

    readonly property var _monthNames: [
        "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
        "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"
    ]
    readonly property var _weekdayLabels: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

    // "Today" is frozen at whatever it was when last computed — refreshed on
    // open (in case the panel sat instantiated-but-closed across midnight)
    // and every minute while it stays open. Opening also re-reads both event
    // backends (ics dir + EDS, M12 Task 3) so the grid isn't up to five
    // minutes stale the moment it becomes visible.
    property date _today: new Date()
    onIsOpenChanged: {
        if (root.isOpen) {
            root._today = new Date();
            CalendarEventsService.refresh();
        }
    }

    Timer {
        interval: 60000
        running: root.isOpen
        repeat: true
        onTriggered: root._today = new Date()
    }

    readonly property int _year: root._today.getFullYear()
    readonly property int _month: root._today.getMonth()
    readonly property real _yearFraction: Progress.yearFraction(root._today)

    // Settings overrides the persisted state value per key (Config's own
    // "settings never written by the shell, always wins when present" rule)
    // — Config.get's own fallback param already resolves this, but going
    // through Progress.resolveOverride keeps the precedence itself pure and
    // unit-tested rather than folded silently into a QML binding.
    readonly property var _birthYear: Progress.resolveOverride(Core.Config.get("calendar.birthYear", undefined), Core.State.calendarBirthYear)
    readonly property var _lifeExpectancy: Progress.resolveOverride(Core.Config.get("calendar.lifeExpectancy", undefined), Core.State.calendarLifeExpectancy)
    readonly property var _lifeFraction: Progress.lifeFraction(root._today, root._birthYear, root._lifeExpectancy)
    readonly property bool _lifeValuesSet: root._lifeFraction !== null

    // Defaults to the life view the moment a valid pair exists (a live
    // binding until the user's own double-click below reassigns it, which
    // QML then treats as a plain stored value — see the toggle handler).
    property bool _showLifeProgress: root._lifeValuesSet

    readonly property real _displayFraction: root._showLifeProgress ? root._lifeFraction : root._yearFraction
    readonly property string _displayLabel: root._showLifeProgress ? "LIFE" : "YEAR"

    // "birthYear" | "lifeExpectancy" | "" — which half of the two-step
    // prompt is currently outstanding, correlated against the token on each
    // menu.selectionResolved.
    property string _pendingStep: ""
    property int _pendingBirthYear: 0

    function _beginLifeEasterEgg() {
        if (!root.menu)
            return;
        root._pendingStep = "birthYear";
        root.menu.openInput("Birth year", "calendar-birth-year");
    }

    function _onProgressDoubleClicked() {
        if (root._lifeValuesSet)
            root._showLifeProgress = !root._showLifeProgress;
        else
            root._beginLifeEasterEgg();
    }

    // menu.openInput() must never be called synchronously from inside this
    // handler: it's itself invoked from within Menu's own _writeSelection(),
    // ahead of the mode/close bookkeeping that call's caller still has left
    // to run, so an immediate re-open would get clobbered the instant that
    // outer call unwinds. Qt.callLater defers it to the next event-loop
    // turn, after Menu has finished settling back to "menu" mode.
    Connections {
        target: root.menu

        function onSelectionResolved(token, value, cancelled) {
            if (token === "calendar-birth-year" && root._pendingStep === "birthYear") {
                if (cancelled) {
                    root._pendingStep = "";
                    return;
                }
                root._pendingBirthYear = parseInt(value, 10);
                root._pendingStep = "lifeExpectancy";
                Qt.callLater(function () {
                    root.menu.openInput("Life expectancy (years)", "calendar-life-expectancy");
                });
            } else if (token === "calendar-life-expectancy" && root._pendingStep === "lifeExpectancy") {
                root._pendingStep = "";
                if (cancelled)
                    return;
                var lifeExpectancy = parseInt(value, 10);
                if (Progress.lifeFraction(root._today, root._pendingBirthYear, lifeExpectancy) !== null)
                    Core.State.setCalendarLifeProgress(root._pendingBirthYear, lifeExpectancy);
            }
        }
    }

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
                // Only in-month cells resolve against root._year/_month —
                // the leading/trailing padding days belong to the adjacent
                // month and are dimmed rather than queried.
                readonly property bool hasEvents: dayCell.modelData.inMonth
                    && CalendarEventsService.onDate(new Date(root._year, root._month, dayCell.modelData.day)).length > 0

                Column {
                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: dayCell.modelData.day
                        color: dayCell.modelData.inMonth ? dayCell.foreground : Core.Theme.color.foregroundDim
                        font.family: Core.Theme.font.family
                        font.pixelSize: Core.Theme.fontSize.body
                    }

                    // Reserved space always present so a day without events
                    // doesn't sit shorter than its row neighbours — flat
                    // accent dot, no glow, per DESIGN.md.
                    Rectangle {
                        width: 4
                        height: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: dayCell.selected ? dayCell.foreground : Core.Theme.color.accent
                        opacity: dayCell.hasEvents ? 1 : 0
                    }
                }
            }
        }
    }

    readonly property var _todaysEvents: CalendarEventsService.onDate(root._today)

    Cell {
        width: parent.width

        MetaLabel {
            text: "TODAY"
        }
    }

    Repeater {
        model: root._todaysEvents.length > 0 ? root._todaysEvents : [null]

        delegate: Cell {
            id: eventCell
            required property var modelData
            width: parent.width

            Text {
                text: eventCell.modelData ? eventCell.modelData.summary : "NO EVENTS"
                color: eventCell.modelData ? eventCell.foreground : Core.Theme.color.foregroundDim
                font.family: Core.Theme.font.family
                font.pixelSize: Core.Theme.fontSize.body
            }
        }
    }

    Cell {
        id: yearCell
        width: parent.width

        Column {
            width: parent.width
            spacing: Core.Theme.spacing.xs

            MetaLabel {
                text: root._displayLabel
            }

            Text {
                text: Progress.formatPercent(root._displayFraction)
                color: yearCell.foreground
                font.family: Core.Theme.font.family
                font.pixelSize: Core.Theme.fontSize.body
            }

            // Flat accent fill, no thumb, no radius — same idiom as
            // AudioPanel's volume slider. Double-click is the life-progress
            // easter egg: prompts for birth year/life expectancy the first
            // time, toggles year<->life once a valid pair exists.
            Rectangle {
                width: parent.width
                height: 6
                color: Core.Theme.color.rule

                Rectangle {
                    width: parent.width * root._displayFraction
                    height: parent.height
                    color: Core.Theme.color.accent
                }

                MouseArea {
                    anchors.fill: parent
                    onDoubleClicked: root._onProgressDoubleClicked()
                }
            }
        }
    }
}

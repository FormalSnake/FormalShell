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
import "../../Clock/model.js" as ClockModel

// Month grid + year-progress popout (DESIGN.md §Panels' clock/calendar
// entry, spec §2, M6 Task 3): a MONTH/YEAR meta row flanked by `<`/`>`
// month-nav cells, then the grid itself — weekday header meta row followed
// by one ledger cell per day, days outside the current month dimmed to
// foregroundFaint — and below it the year-progress bar as a full-width flat
// accent-fill cell with its percentage as mono text, mirroring AudioPanel's
// slider idiom. Day selection (M13 Task 4): every day cell is clickable
// (hover-cursor state, DESIGN §1.1); the selected day carries Cell's fg/bg
// inversion and drives the events ledger below the grid, whose meta header
// reads TODAY for today or the short uppercase date (JUL 31) otherwise.
// Today keeps a full-bleed accent fill (DESIGN §2.4, the focused-workspace
// idiom) whenever it is not itself the selected day, so both states stay
// visible at once when they differ. Month navigation RESETS selection to
// today rather than clamping the day-of-month — a clamped selection would
// silently show events for a day the user never picked. Clicking an
// adjacent-month padding day selects it and aligns the view to its month
// (as does `calendar select <iso-date>` over IPC — CalendarIpc, the smoke
// rig's drive path), so a visible selection is always an in-month cell;
// opening the panel resets both the view month and the selection to today.
// Modeled on Omarchy quattro's calendar widget (read only, not copied —
// CLAUDE.md's read-reference rule for that repo). The
// life-progress easter egg (M6 Task 4): double-clicking the year-progress
// bar prompts, through the menu's existing "input" mode, first for birth
// year then life expectancy; both persist to state.json via
// State.setCalendarLifeProgress(), mirroring wallpaper/mode/dnd's own alias
// + writeAdapter pattern. settings.json's calendar.birthYear/
// calendar.lifeExpectancy declaratively override the persisted state
// values when present (Progress.resolveOverride: settings wins, state is
// the fallback). Once both resolve to a valid pair a life-progress row
// appears alongside the year row rather than replacing it (M20 Task 5e —
// the easter egg used to swap the bar's content entirely); a further
// double-click hides the life row again, leaving the year row untouched
// either way. Events (M6 Task 5): a small
// accent dot under any in-month day that has one, sourced from
// CalendarEventsService's local .ics reader (docs/spikes/2026-07-28-eds-
// calendar-events.md records why EDS/GOA over D-Bus lost to that fallback);
// the events ledger section below the grid lists the selected day's events
// by summary, or a single dim "NO EVENTS" row when there are none — the
// honest-empty-state every other panel backend already follows in the test
// VM.
//
// M26 Task 4: the panel opens with the shared PanelHero (weekday as title,
// today's day-of-month as the display readout, the year row's own fraction
// doubling as the hero's rail). The grid always renders 6 week rows so
// stepping months never resizes the card, with an ISO week-number column
// (ClockModel.isoWeek, shared with the bar clock's own ISO-week format
// preset) down the left in foregroundFaint.
Panel {
    id: root

    panelTitle: "CALENDAR"
    // Wide, not narrow: this grid carries eight columns (the ISO week number
    // plus seven days) and a hero, and at the narrow step the day cells were
    // tighter than anything else in the shell. Upstream's own clock popup runs
    // at 560 for the same content; 400 is the widest step DESIGN.md sanctions
    // for a bar-anchored panel, 560 being reserved for the menu.
    panelWidth: Core.Theme.space.popupWidthWide

    // Set from shell.qml, the single Menu instance, needed to drive the
    // life-progress easter egg's two-step birth-year/life-expectancy prompt
    // through the menu's own input mode (M6 Task 4).
    property var menu: null

    // Locale month name (QML's Locale.monthName takes 0-11, matching JS
    // Date, unlike the C++ QLocale API it wraps). MetaLabel's own
    // Font.AllUppercase renders this the same as the hand-built array it
    // replaces (M26 Task 4) whatever case the locale returns.
    function _monthName(month) {
        return Qt.locale().monthName(month, Locale.LongFormat);
    }
    readonly property var _monthShort: [
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
        "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
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
            root._viewYear = root._today.getFullYear();
            root._viewMonth = root._today.getMonth();
            root._selected = root._today;
            CalendarEventsService.refresh();
        }
    }

    Timer {
        interval: 60000
        running: root.isOpen
        repeat: true
        onTriggered: root._today = new Date()
    }

    // The month the grid displays — decoupled from _today by the `<`/`>`
    // nav cells, re-anchored to today on every open (see onIsOpenChanged).
    property int _viewYear: new Date().getFullYear()
    property int _viewMonth: new Date().getMonth()
    // The day whose events the ledger below the grid lists. Defaults to
    // today; reset to today on open and on month navigation (the documented
    // reset-not-clamp choice, header comment above).
    property date _selected: new Date()
    readonly property real _yearFraction: Progress.yearFraction(root._today)

    function _isSameDate(a, b) {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate();
    }

    function _isoDate(d) {
        var m = d.getMonth() + 1;
        var day = d.getDate();
        return d.getFullYear() + "-" + (m < 10 ? "0" + m : m) + "-" + (day < 10 ? "0" + day : day);
    }

    function _selectDate(d) {
        root._selected = d;
        root._viewYear = d.getFullYear();
        root._viewMonth = d.getMonth();
    }

    function _stepMonth(delta) {
        var m = root._viewMonth + delta;
        root._viewYear += Math.floor(m / 12);
        root._viewMonth = ((m % 12) + 12) % 12;
        root._selected = root._today;
    }

    // IPC entry (CalendarIpc's `select` verb): strict YYYY-MM-DD only, with
    // a component round-trip so 2026-02-31 is rejected rather than silently
    // becoming March 3rd.
    function selectIsoDate(iso) {
        var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
        if (!m)
            return false;
        var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
        if (d.getFullYear() !== Number(m[1]) || d.getMonth() !== Number(m[2]) - 1 || d.getDate() !== Number(m[3]))
            return false;
        root._selectDate(d);
        return true;
    }

    // IPC entry (CalendarIpc's `status` verb).
    function selectionStatus() {
        return {
            open: root.isOpen,
            selected: root._isoDate(root._selected),
            today: root._isoDate(root._today),
            view: root._monthName(root._viewMonth) + " " + root._viewYear
        };
    }

    // Settings overrides the persisted state value per key (Config's own
    // "settings never written by the shell, always wins when present" rule)
    // — Config.get's own fallback param already resolves this, but going
    // through Progress.resolveOverride keeps the precedence itself pure and
    // unit-tested rather than folded silently into a QML binding.
    readonly property var _birthYear: Progress.resolveOverride(Core.Config.get("calendar.birthYear", undefined), Core.State.calendarBirthYear)
    readonly property var _lifeExpectancy: Progress.resolveOverride(Core.Config.get("calendar.lifeExpectancy", undefined), Core.State.calendarLifeExpectancy)
    readonly property var _lifeFraction: Progress.lifeFraction(root._today, root._birthYear, root._lifeExpectancy)
    readonly property bool _lifeValuesSet: root._lifeFraction !== null

    // Defaults to showing the life row the moment a valid pair exists (a
    // live binding until the user's own double-click below reassigns it,
    // which QML then treats as a plain stored value — see the toggle
    // handler). The year row is unconditional — this flag only ever adds or
    // removes the life row alongside it, never swaps it out (M20 Task 5e).
    property bool _showLifeProgress: root._lifeValuesSet

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

    // Monday-first grid, always 6 rows/42 cells regardless of month length
    // (M26 Task 4) so stepping months never resizes the card — a 28-day
    // February and a 31-day month both pad out with dimmed leading/trailing
    // days from the adjacent months. Each cell carries its fully resolved
    // year/month so a padding-day click can select the real adjacent-month
    // date; today/selected are compared in the delegate (live bindings)
    // rather than baked in here.
    readonly property var _cells: {
        var year = root._viewYear;
        var month = root._viewMonth;
        var firstWeekday = (new Date(year, month, 1).getDay() + 6) % 7;
        var start = new Date(year, month, 1 - firstWeekday);
        var cells = [];
        for (var i = 0; i < 42; i++) {
            var d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            cells.push({ year: d.getFullYear(), month: d.getMonth(), day: d.getDate(), inMonth: d.getMonth() === month && d.getFullYear() === year });
        }
        return cells;
    }

    // One ISO week number per grid row, read off that row's Thursday
    // (index 3 of its 7 Monday-first cells) — the definition of the week a
    // row belongs to whenever the row's days span a month or year boundary.
    readonly property var _weekNumbers: {
        var weeks = [];
        for (var r = 0; r < 6; r++) {
            var thursday = root._cells[r * 7 + 3];
            weeks.push(ClockModel.isoWeek(thursday.year, thursday.month, thursday.day));
        }
        return weeks;
    }

    // Same fixed slot width PanelHero gives its own leading glyph column —
    // wide enough for two digits, narrow enough to read as a margin rather
    // than an eighth day column.
    readonly property real _weekColumnWidth: Core.Theme.space.xxl * 2

    // Month swap (DESIGN.md §4): the regenerated grid fades in on view
    // change — a crossfade would need a second live grid instance for no
    // visible gain. restart() makes rapid `<`/`>` stepping interruptible
    // (each step re-fades from wherever the last one got to zero).
    readonly property string _viewKey: root._viewYear + "-" + root._viewMonth
    on_ViewKeyChanged: if (root.isOpen) monthSwapAnim.restart()

    NumberAnimation {
        id: monthSwapAnim
        target: dayGrid
        property: "opacity"
        from: 0
        to: 1
        duration: Core.Theme.motion.standard
        easing.type: Core.Theme.motion.easing
    }

    // Calendar hero: weekday as the title, today's day-of-month as the display
    // readout (the surrounding month/year already sits in monthNav below), and
    // today's ISO week as the meta line, which is the one fact about today the
    // grid below cannot state without the reader counting rows.
    //
    // The hero deliberately carries NO rail. It briefly mirrored the year
    // fraction, which put the same percentage and the same bar on screen twice
    // over: once here and once in the YEAR ledger cell further down, which owns
    // that number along with its full header/percent/rail chrome and its
    // double-click life-progress easter egg. Upstream keeps its year and life
    // bars as their own rows under the grid for the same reason.
    PanelHero {
        width: parent.width
        title: Qt.locale().dayName(root._today.getDay(), Locale.LongFormat)
        meta: "WEEK " + ClockModel.pad2(ClockModel.isoWeek(
            root._today.getFullYear(), root._today.getMonth(), root._today.getDate()))
        readout: String(root._today.getDate())
    }

    Row {
        id: monthNav
        width: parent.width

        Cell {
            width: monthNav.width / 7

            MetaLabel {
                anchors.centerIn: parent
                text: "<"
            }

            interactive: true
            onClicked: root._stepMonth(-1)
        }

        Cell {
            width: monthNav.width - monthNav.width / 7 * 2

            MetaLabel {
                anchors.centerIn: parent
                text: root._monthName(root._viewMonth) + " " + root._viewYear
            }
        }

        Cell {
            width: monthNav.width / 7

            MetaLabel {
                anchors.centerIn: parent
                text: ">"
            }

            interactive: true
            onClicked: root._stepMonth(1)
        }
    }

    Row {
        id: calendarGrid
        width: parent.width

        // ISO week-number column (M26 Task 4): a blank header cell over
        // one number per grid row, quiet enough (foregroundFaint) to never
        // compete with the dates it sits beside.
        Column {
            id: weekColumn
            width: root._weekColumnWidth

            Cell {
                width: weekColumn.width

                // Blank, not omitted: an empty MetaLabel still measures the
                // same line height as the weekday header cells beside it, so
                // the two header rows stay level.
                MetaLabel {
                    anchors.centerIn: parent
                    text: ""
                }
            }

            Repeater {
                model: root._weekNumbers

                delegate: Cell {
                    id: weekNumberCell
                    required property int modelData
                    width: weekColumn.width

                    // Same Text-plus-reserved-space shape as a day cell
                    // (below), so this row's height matches its day-grid
                    // neighbours row for row rather than running short.
                    Column {
                        anchors.centerIn: parent
                        spacing: Core.Theme.space.xxs

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: ClockModel.pad2(weekNumberCell.modelData)
                            color: Core.Theme.color.foregroundFaint
                            font.family: Core.Theme.fontFamily
                            font.pixelSize: Core.Theme.fontSize.body
                        }

                        Item {
                            width: Core.Theme.space.sm
                            height: Core.Theme.space.sm
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }

        Grid {
            id: dayGrid
            width: calendarGrid.width - weekColumn.width
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
                    // Selection inversion and today's accent fill apply to
                    // in-month cells only — padding days stay purely dim even
                    // when they happen to be today/selected in their own month
                    // (both are transient: selecting a padding day immediately
                    // realigns the view, see the header comment).
                    readonly property bool isToday: dayCell.modelData.inMonth
                        && dayCell.modelData.day === root._today.getDate()
                        && dayCell.modelData.month === root._today.getMonth()
                        && dayCell.modelData.year === root._today.getFullYear()
                    readonly property bool isSelected: dayCell.modelData.inMonth
                        && dayCell.modelData.day === root._selected.getDate()
                        && dayCell.modelData.month === root._selected.getMonth()
                        && dayCell.modelData.year === root._selected.getFullYear()
                    selected: dayCell.isSelected
                    accent: dayCell.isToday && !dayCell.isSelected
                    // Only in-month cells query events — the leading/trailing
                    // padding days belong to the adjacent month and are dimmed
                    // rather than dotted.
                    readonly property bool hasEvents: dayCell.modelData.inMonth
                        && CalendarEventsService.onDate(new Date(dayCell.modelData.year, dayCell.modelData.month, dayCell.modelData.day)).length > 0

                    Column {
                        anchors.centerIn: parent
                        spacing: Core.Theme.space.xxs

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayCell.modelData.day
                            color: dayCell.modelData.inMonth ? dayCell.foreground : Core.Theme.color.foregroundFaint
                            font.family: Core.Theme.fontFamily
                            font.pixelSize: Core.Theme.fontSize.body
                        }

                        // Reserved space always present so a day without events
                        // doesn't sit shorter than its row neighbours — flat
                        // accent dot, no glow, per DESIGN.md.
                        Rectangle {
                            width: Core.Theme.space.sm
                            height: Core.Theme.space.sm
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: (dayCell.selected || dayCell.accent) ? dayCell.foreground : Core.Theme.color.accent
                            opacity: dayCell.hasEvents ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation { duration: Core.Theme.motion.fast; easing.type: Core.Theme.motion.easing }
                            }
                        }
                    }

                    interactive: true
                    onClicked: root._selectDate(new Date(dayCell.modelData.year, dayCell.modelData.month, dayCell.modelData.day))
                }
            }
        }
    }

    readonly property bool _selectedIsToday: root._isSameDate(root._selected, root._today)
    readonly property var _selectedEvents: CalendarEventsService.onDate(root._selected)

    Cell {
        width: parent.width

        MetaLabel {
            text: root._selectedIsToday
                ? "TODAY"
                : root._monthShort[root._selected.getMonth()] + " " + root._selected.getDate()
            colon: true
        }
    }

    Repeater {
        model: root._selectedEvents.length > 0 ? root._selectedEvents : [null]

        delegate: Cell {
            id: eventCell
            required property var modelData
            width: parent.width

            Text {
                text: eventCell.modelData ? eventCell.modelData.summary : "NO EVENTS"
                color: eventCell.modelData ? eventCell.foreground : Core.Theme.color.foregroundDim
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.body
            }
        }
    }

    Cell {
        id: yearCell
        width: parent.width

        Column {
            width: parent.width
            spacing: Core.Theme.space.xxs

            MetaLabel {
                text: "YEAR"
            }

            Text {
                text: Progress.formatPercent(root._yearFraction)
                color: yearCell.foreground
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.body
            }

            // Flat accent fill, no thumb, no radius — same idiom as
            // AudioPanel's volume slider. Double-click is the life-progress
            // easter egg: prompts for birth year/life expectancy the first
            // time, then toggles the LIFE row below on/off. It never
            // replaces this row (M20 Task 5e) — the easter egg adds, never
            // swaps.
            DitherFill {
                width: parent.width
                height: Core.Theme.space.trackThickness

                Rectangle {
                    width: parent.width * root._yearFraction
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

    // The life-progress row (M6 Task 4, coexists rather than replaces as of
    // M20 Task 5e): same track idiom and tokens as the year row above,
    // shown only once a valid birth-year/life-expectancy pair exists and
    // the easter egg is toggled on.
    Cell {
        id: lifeCell
        width: parent.width
        visible: root._showLifeProgress

        Column {
            width: parent.width
            spacing: Core.Theme.space.xxs

            MetaLabel {
                text: "LIFE"
            }

            Text {
                text: Progress.formatPercent(root._lifeFraction)
                color: lifeCell.foreground
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.body
            }

            DitherFill {
                width: parent.width
                height: Core.Theme.space.trackThickness

                Rectangle {
                    width: parent.width * root._lifeFraction
                    height: parent.height
                    color: Core.Theme.color.accent
                }
            }
        }
    }
}

import QtQuick
// Aliased, not a bare `import qs.Core`: QtQuick already exports a type
// named State (for property-binding states), and an unqualified import
// loses that name collision, so State.calendarBirthYear reads back
// undefined at runtime instead of hitting the qs.Core singleton (the M24
// chevron trap, CLAUDE.md). Importing qs.Core a second time unqualified
// alongside this one breaks qmllint's module resolution entirely, so every
// reference in this file goes through the Core. prefix.
import qs.Core as Core
import qs.Components
import qs.Services
import "../../Calendar/agenda.js" as Agenda
import "../../Calendar/grid.js" as CalGrid
import "../../Calendar/progress.js" as Progress
import "../../Clock/model.js" as ClockModel

// Calendar panel (DESIGN.md §3 "Panel", spec "Panels"): a hero naming today,
// a month grid of day cells under a weekday section label, the selected
// day's events as rows, and the year and life progress tracks below them.
// Wide, since the grid carries eight columns (the ISO week number plus seven
// days).
//
// Keyboard (spec "Keyboard model"): the cursor addresses the 42 grid cells,
// so all four arrows walk it as a grid (Panel's `cursorColumns`), Left and
// Right stop at the ends of their own week rather than stepping the month,
// and Enter selects the day under the cursor. `[` and `]` step the month, as
// do the two header chevrons. Selecting a padding day realigns the view to
// that day's own month, so a visible selection is always an in-month cell.
// The grid maths (which 42 days, which ISO weeks, index to date, the event
// dot) lives in Calendar/grid.js.
//
// Events (M6 Task 5) come from CalendarEventsService's local .ics reader and
// EDS (docs/spikes/2026-07-28-eds-calendar-events.md records why EDS over
// D-Bus lost to the .ics fallback). Calendar/agenda.js shapes the day: all
// day events first, then the timed ones chronologically, each row's time in
// mono and its summary in sans. An event already over drops its time to
// mutedForeground; the one currently running is marked NOW in the section
// label, which also carries the next start time on today.
//
// The life progress easter egg (M6 Task 4): double-clicking the year track
// prompts, through the menu's existing "input" mode, first for birth year
// then life expectancy; both persist to state.json via
// State.setCalendarLifeProgress(). settings.json's calendar.birthYear and
// calendar.lifeExpectancy declaratively override the persisted values
// (Progress.resolveOverride). Once both resolve, a life row appears
// alongside the year row rather than replacing it (M20 Task 5e); a further
// double-click hides it again.
Panel {
    id: root

    panelIcon: "calendar"
    panelTitle: "Calendar"
    panelWidth: Core.Theme.space.popupWidthWide

    // Set from shell.qml, the single Menu instance, needed to drive the
    // life-progress easter egg's two-step prompt through the menu's own
    // input mode (M6 Task 4).
    property var menu: null

    // Locale month name (QML's Locale.monthName takes 0-11, matching JS
    // Date, unlike the C++ QLocale API it wraps).
    function _monthName(month) {
        return Qt.locale().monthName(month, Locale.LongFormat);
    }
    readonly property var _monthShort: [
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
        "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
    ]
    readonly property var _weekdayLabels: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

    // "Today" is frozen at whatever it was when last computed, refreshed on
    // open (in case the panel sat instantiated-but-closed across midnight)
    // and every minute while it stays open. Opening also re-reads both event
    // backends (M12 Task 3) so the grid isn't up to five minutes stale the
    // moment it becomes visible.
    property date _today: new Date()

    Timer {
        interval: 60000
        running: root.isOpen
        repeat: true
        onTriggered: root._today = new Date()
    }

    // The month the grid displays, decoupled from _today by the header
    // chevrons and re-anchored to today on every open.
    property int _viewYear: new Date().getFullYear()
    property int _viewMonth: new Date().getMonth()
    // The day whose events the rows below the grid list. Month navigation
    // resets it to today rather than clamping the day-of-month: a clamped
    // selection would silently show events for a day nobody picked.
    property date _selected: new Date()
    readonly property real _yearFraction: Progress.yearFraction(root._today)

    readonly property var _cells: CalGrid.monthCells(root._viewYear, root._viewMonth)
    readonly property var _weekNumbers: CalGrid.weekNumbers(root._cells)

    function _selectDate(d) {
        root._selected = d;
        root._viewYear = d.getFullYear();
        root._viewMonth = d.getMonth();
        root.cursorIndex = CalGrid.indexOfDate(root._cells, d);
    }

    function _stepMonth(delta) {
        var next = CalGrid.stepMonth(root._viewYear, root._viewMonth, delta);
        root._viewYear = next.year;
        root._viewMonth = next.month;
        root._selected = root._today;
        root.cursorIndex = CalGrid.indexOfDate(root._cells, root._selected);
    }

    // IPC entry (CalendarIpc's `select` verb).
    function selectIsoDate(iso) {
        var d = CalGrid.parseIsoDate(iso);
        if (!d)
            return false;
        root._selectDate(d);
        return true;
    }

    // IPC entry (CalendarIpc's `status` verb).
    function selectionStatus() {
        return {
            open: root.isOpen,
            selected: CalGrid.isoDate(root._selected),
            today: CalGrid.isoDate(root._today),
            view: root._monthName(root._viewMonth) + " " + root._viewYear
        };
    }

    cursorColumns: CalGrid.COLUMNS
    cursorCount: root._cells.length

    onCursorActivated: index => {
        var d = CalGrid.dateAt(root._cells, index);
        if (d)
            root._selectDate(d);
    }

    onCursorTextKey: text => {
        if (text === "[")
            root._stepMonth(-1);
        else if (text === "]")
            root._stepMonth(1);
    }

    onIsOpenChanged: {
        if (!root.isOpen)
            return;
        root._today = new Date();
        root._viewYear = root._today.getFullYear();
        root._viewMonth = root._today.getMonth();
        root._selected = root._today;
        root.cursorIndex = CalGrid.indexOfDate(root._cells, root._today);
        CalendarEventsService.refresh();
    }

    titleActions: [
        IconButton {
            name: "chevron-left"
            onClicked: root._stepMonth(-1)
        },
        IconButton {
            name: "chevron-right"
            onClicked: root._stepMonth(1)
        }
    ]

    // Settings overrides the persisted state value per key (Config's own
    // "settings never written by the shell, always wins when present" rule).
    // Config.get's own fallback param already resolves this, but going
    // through Progress.resolveOverride keeps the precedence itself pure and
    // unit-tested rather than folded silently into a QML binding.
    readonly property var _birthYear: Progress.resolveOverride(Core.Config.get("calendar.birthYear", undefined), Core.State.calendarBirthYear)
    readonly property var _lifeExpectancy: Progress.resolveOverride(Core.Config.get("calendar.lifeExpectancy", undefined), Core.State.calendarLifeExpectancy)
    readonly property var _lifeFraction: Progress.lifeFraction(root._today, root._birthYear, root._lifeExpectancy)
    readonly property bool _lifeValuesSet: root._lifeFraction !== null

    // Defaults to showing the life row the moment a valid pair exists (a
    // live binding until the user's own double-click below reassigns it,
    // which QML then treats as a plain stored value). The year row is
    // unconditional: this flag only ever adds or removes the life row
    // alongside it (M20 Task 5e).
    property bool _showLifeProgress: root._lifeValuesSet

    // "birthYear" | "lifeExpectancy" | "", which half of the two-step prompt
    // is currently outstanding, correlated against the token on each
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

    // Month swap (DESIGN.md §1 "Motion"): the regenerated grid fades in on
    // view change, since a crossfade would need a second live grid instance
    // for no visible gain. restart() makes rapid stepping interruptible.
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

    readonly property bool _selectedIsToday: CalGrid.sameDate(root._selected, root._today)
    readonly property var _selectedEvents: Agenda.sortForDay(CalendarEventsService.onDate(root._selected))
    // The clock's format ring encodes notation, not just layout: each
    // 12-hour preset is its neighbour's AM/PM twin, so the agenda writes its
    // times in whichever notation the bar clock is currently set to instead
    // of carrying a setting of its own.
    readonly property bool _twelveHour: ClockModel.usesMeridiem(
        Core.State.clockFormat !== "" ? Core.State.clockFormat : ClockModel.CLOCK_FORMATS[0])
    // `_today` is re-read every minute while the panel is open (the Timer
    // above), so both of these, and every row's own status, move with the
    // clock rather than freezing at whatever the open captured.
    readonly property var _agendaNext: root._selectedIsToday ? Agenda.nextUp(root._selectedEvents, root._today) : null
    readonly property bool _agendaNow: root._selectedIsToday && Agenda.hasRunning(root._selectedEvents, root._today)

    // Today's own subject: the weekday, its ISO week (the one fact about
    // today the grid cannot state without the reader counting rows) and the
    // day of the month as the readout.
    PanelHero {
        width: parent.width
        title: Qt.locale().dayName(root._today.getDay(), Locale.LongFormat)
        meta: "Week " + ClockModel.pad2(ClockModel.isoWeek(
            root._today.getFullYear(), root._today.getMonth(), root._today.getDate()))
        readout: String(root._today.getDate())
    }

    Column {
        width: parent.width
        spacing: Core.Theme.space.rowGap

        SectionLabel {
            leftPadding: Core.Theme.space.controlPaddingX
            text: root._monthName(root._viewMonth) + " " + root._viewYear
        }

        Row {
            id: calendarGrid
            width: parent.width
            spacing: Core.Theme.space.rowGap

            // ISO week-number column: a gutter of muted mono numbers rather
            // than an eighth day column, so nothing about it reads as a
            // selectable date. The header slot is blank but present, which
            // is what keeps it level with the weekday row beside it.
            Column {
                id: weekColumn
                width: Core.Theme.space.xl
                spacing: Core.Theme.space.rowGap

                SectionLabel {
                    width: weekColumn.width
                    text: ""
                    horizontalAlignment: Text.AlignHCenter
                }

                Repeater {
                    model: root._weekNumbers

                    delegate: Item {
                        id: weekNumberCell
                        required property int modelData
                        width: weekColumn.width
                        height: dayGrid.cellHeight

                        Text {
                            anchors.centerIn: parent
                            text: ClockModel.pad2(weekNumberCell.modelData)
                            color: Core.Theme.color.mutedForeground
                            font.family: Core.Theme.fontFamilyMono
                            font.pixelSize: Core.Theme.fontSize.caption
                        }
                    }
                }
            }

            Grid {
                id: dayGrid
                width: calendarGrid.width - weekColumn.width - calendarGrid.spacing
                columns: CalGrid.COLUMNS
                rowSpacing: Core.Theme.space.rowGap
                columnSpacing: Core.Theme.space.rowGap

                readonly property real cellWidth: (dayGrid.width - columnSpacing * (CalGrid.COLUMNS - 1)) / CalGrid.COLUMNS
                // Square-ish day cells, measured off one so every row lines
                // up with the week gutter beside it.
                readonly property real cellHeight: measureCell.implicitHeight

                Repeater {
                    model: root._weekdayLabels

                    delegate: SectionLabel {
                        id: weekdayCell
                        required property string modelData
                        width: dayGrid.cellWidth
                        text: weekdayCell.modelData
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Repeater {
                    model: root._cells

                    delegate: Cell {
                        id: dayCell
                        required property var modelData
                        required property int index
                        width: dayGrid.cellWidth
                        height: dayGrid.cellHeight
                        // One level inside the panel's own radiusXl frame
                        // (spec "Radius", the concentric rule).
                        radius: Core.Theme.radiusSm
                        interactive: true

                        // Today and the selection apply to in-month cells
                        // only: a padding day is transient, since selecting
                        // one immediately realigns the view to its month.
                        readonly property bool _isToday: dayCell.modelData.inMonth
                            && CalGrid.sameDate(new Date(dayCell.modelData.year, dayCell.modelData.month, dayCell.modelData.day), root._today)
                        readonly property bool _isSelected: dayCell.modelData.inMonth
                            && CalGrid.sameDate(new Date(dayCell.modelData.year, dayCell.modelData.month, dayCell.modelData.day), root._selected)
                        readonly property int _eventCount: dayCell.modelData.inMonth
                            ? CalendarEventsService.onDate(new Date(dayCell.modelData.year, dayCell.modelData.month, dayCell.modelData.day)).length
                            : 0

                        active: dayCell._isToday && !dayCell._isSelected
                        selected: dayCell._isSelected
                        cursor: root.cursorActive && root.cursorIndex === dayCell.index

                        onContainsPointerChanged: if (dayCell.containsPointer) {
                            root.cursorActive = true;
                            root.cursorIndex = dayCell.index;
                        }

                        onClicked: root._selectDate(new Date(dayCell.modelData.year, dayCell.modelData.month, dayCell.modelData.day))

                        Column {
                            anchors.centerIn: parent
                            spacing: Core.Theme.space.xxs

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: dayCell.modelData.day
                                color: dayCell.modelData.inMonth ? dayCell.foreground : Core.Theme.color.mutedForeground
                                font.family: Core.Theme.fontFamilyMono
                                font.pixelSize: Core.Theme.fontSize.bodySmall
                            }

                            // Reserved space always present, so a day
                            // without events doesn't sit shorter than its
                            // row neighbours.
                            // primitive-exempt: an event dot under a day number. A dot is an
                            // indicator, not a surface; no primitive draws one.
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Core.Theme.space.xs
                                height: Core.Theme.space.xs
                                radius: Core.Theme.pillRadius(width)
                                color: (dayCell.active || dayCell.selected) ? dayCell.foreground : Core.Theme.color.primary
                                opacity: CalGrid.showsEventDot(dayCell.modelData, dayCell._eventCount) ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: Core.Theme.motion.fast; easing.type: Core.Theme.motion.easing }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Off-layout gauge, not a rendered row: Column skips an invisible child
    // entirely, so this costs no space while giving every day cell one
    // height to share, measured from a real cell rather than a guess.
    Cell {
        id: measureCell
        visible: false
        radius: Core.Theme.radiusSm

        Column {
            spacing: Core.Theme.space.xxs

            Text {
                text: "00"
                font.family: Core.Theme.fontFamilyMono
                font.pixelSize: Core.Theme.fontSize.bodySmall
            }

            Item {
                width: Core.Theme.space.xs
                height: Core.Theme.space.xs
            }
        }
    }

    // The same trick for the day's event rows: one width for every time
    // column, measured from the widest label the day actually prints rather
    // than from a character count, which would only hold in a mono font.
    Text {
        id: agendaGauge
        visible: false
        text: Agenda.widestLabel(root._selectedEvents, root._twelveHour)
        font.family: Core.Theme.fontFamilyMono
        font.pixelSize: Core.Theme.fontSize.bodySmall
    }

    Column {
        width: parent.width
        spacing: Core.Theme.space.rowGap

        Item {
            width: parent.width
            height: agendaLabel.implicitHeight

            SectionLabel {
                id: agendaLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: Core.Theme.space.controlPaddingX
                text: root._selectedIsToday
                    ? "TODAY"
                    : root._monthShort[root._selected.getMonth()] + " " + root._selected.getDate()
                count: root._selectedEvents.length
            }

            SectionLabel {
                anchors.right: parent.right
                anchors.rightMargin: Core.Theme.space.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                visible: root._agendaNow || root._agendaNext !== null
                text: root._agendaNow
                    ? "NOW"
                    : root._agendaNext !== null ? "NEXT " + Agenda.clockTime(root._agendaNext.start, root._twelveHour) : ""
            }
        }

        SectionLabel {
            visible: root._selectedEvents.length === 0
            leftPadding: Core.Theme.space.controlPaddingX
            text: "NO EVENTS"
        }

        // A borderless row leaves no box for a gap to sit between, so the rows
        // in a section abut and only `sectionGap` separates the sections.
        Column {
            width: parent.width
            spacing: 0

            Repeater {
                model: root._selectedEvents

                delegate: Cell {
                    id: eventCell
                    required property var modelData
                    width: parent.width
                    ghost: true

                    readonly property string _status: Agenda.status(eventCell.modelData, root._today)

                    Item {
                        width: parent.width
                        height: Math.max(eventTime.implicitHeight, eventSummary.implicitHeight)

                        Text {
                            id: eventTime
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: agendaGauge.implicitWidth
                            text: Agenda.timeLabel(eventCell.modelData, root._twelveHour)
                            color: eventCell._status === "past" ? Core.Theme.color.mutedForeground : eventCell.foreground
                            font.family: Core.Theme.fontFamilyMono
                            font.pixelSize: Core.Theme.fontSize.bodySmall
                        }

                        Text {
                            id: eventSummary
                            anchors.left: eventTime.right
                            anchors.leftMargin: Core.Theme.space.iconGap
                            anchors.right: nowMark.left
                            anchors.rightMargin: Core.Theme.space.iconGap
                            anchors.verticalCenter: parent.verticalCenter
                            text: eventCell.modelData.summary
                            color: eventCell.foreground
                            elide: Text.ElideRight
                            font.family: Core.Theme.fontFamilySans
                            font.pixelSize: Core.Theme.fontSize.body
                            font.weight: Core.Theme.weight.medium
                        }

                        // The running event carries the mark rather than a
                        // full-bleed fill (DESIGN.md §5).
                        SectionLabel {
                            id: nowMark
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: eventCell._status === "now"
                            text: "NOW"
                            color: Core.Theme.color.primary
                        }
                    }
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: Core.Theme.space.rowGap

        SectionLabel { leftPadding: Core.Theme.space.controlPaddingX; text: "PROGRESS" }

        Cell {
            id: yearCell
            width: parent.width

            Column {
                width: parent.width
                spacing: Core.Theme.space.xxs

                Item {
                    width: parent.width
                    height: yearLabel.implicitHeight

                    SectionLabel {
                        id: yearLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "YEAR"
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: Progress.formatPercent(root._yearFraction)
                        color: yearCell.foreground
                        font.family: Core.Theme.fontFamilyMono
                        font.pixelSize: Core.Theme.fontSize.bodySmall
                    }
                }

                Track {
                    width: parent.width
                    value: root._yearFraction
                }
            }

            // The life-progress easter egg: prompts for birth year and life
            // expectancy the first time, then toggles the LIFE row below on
            // and off. It never replaces this row (M20 Task 5e), it adds.
            //
            // The whole cell is the target, not just the track underneath
            // it: that track is `trackThickness` tall, so aiming two clicks
            // into it was the actual reason this went untriggerable. An
            // easter egg may be undocumented and still has to be hittable
            // once you know where it is. Anchored to fill, which Cell
            // excludes from its own implicit size, so covering the row costs
            // the row no height.
            MouseArea {
                anchors.fill: parent
                onDoubleClicked: root._onProgressDoubleClicked()
            }
        }

        Cell {
            id: lifeCell
            width: parent.width
            visible: root._showLifeProgress

            Column {
                width: parent.width
                spacing: Core.Theme.space.xxs

                Item {
                    width: parent.width
                    height: lifeLabel.implicitHeight

                    SectionLabel {
                        id: lifeLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "LIFE"
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: Progress.formatPercent(root._lifeFraction)
                        color: lifeCell.foreground
                        font.family: Core.Theme.fontFamilyMono
                        font.pixelSize: Core.Theme.fontSize.bodySmall
                    }
                }

                Track {
                    width: parent.width
                    value: root._lifeFraction === null ? 0 : root._lifeFraction
                }
            }
        }
    }
}

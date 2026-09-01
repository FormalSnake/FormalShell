import QtQuick
// Aliased, not a bare `import qs.Core`: reaching Core.State (the format
// ring's persisted choice) alongside a bare import loses the singleton to
// QtQuick's own colliding `State` name (the M24 chevron trap, CLAUDE.md).
// Every Core.* reference in this file goes through the Core. prefix, not
// just the new ones, since qmllint's module resolution breaks the moment
// qs.Core is imported both ways in one file.
import qs.Core as Core
import qs.Components
import "../../../Clock/model.js" as ClockModel

// Bar cell for the wall clock (DESIGN.md §3 Bar, M23: single-line like
// every other widget here). Left and middle click both toggle the calendar
// panel anchored under this cell (upstream's redundant left/middle idiom,
// `manual/05-the-top-bar.md`'s Audio row), same open-panel underline
// as Battery.qml. Right click cycles ClockModel's format ring (M26 Task 4)
// and persists the choice through Core.State, never settings.json (the
// shell only ever reads that file). Every ring entry renders through
// Qt.formatDateTime; the ISO-week preset substitutes its 'ww' token by
// hand first since Qt has no ISO-week specifier of its own.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    property date _now: new Date()

    readonly property string _format: Core.State.clockFormat !== "" ? Core.State.clockFormat : ClockModel.CLOCK_FORMATS[0]
    readonly property string _text: Qt.formatDateTime(root._now, ClockModel.substituteIsoWeek(root._format, root._now))

    // The ring's presets differ wildly in extent ("hh:mm" versus
    // "yyyy-MM-dd hh:mm"), glide the swap instead of shoving every other
    // cell in the region instantly (DESIGN.md §4, M16 Task 2's contract).
    // Both axes, since which one the swap moves is the bar's edge.
    Behavior on implicitWidth {
        enabled: root.animateSize
        NumberAnimation { duration: Core.Theme.motion.standard; easing.type: Core.Theme.motion.easingInOut }
    }

    Behavior on implicitHeight {
        enabled: root.animateSize
        NumberAnimation { duration: Core.Theme.motion.standard; easing.type: Core.Theme.motion.easingInOut }
    }

    // One line per field on a vertical bar (ClockModel.stackedLines), the
    // whole preset on one line anywhere else. The same lockup either way, so
    // the digits stand up on all four edges: 44px of strip holds "09" over
    // "41" but nothing holds "09:41" across it.
    CellRow {
        spacing: root.vertical ? 0 : Core.Theme.space.xs

        Repeater {
            model: root.vertical ? ClockModel.stackedLines(root._text) : [root._text]

            CellLabel {
                required property string modelData
                text: modelData
            }
        }
    }

    panelOpen: root._panelOpen

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root._now = new Date()
    }

    interactive: true
    // M26 Task 9's trailing hint states the right-click action, otherwise
    // it's undiscoverable. Middle also opens the panel, added below.
    tooltipText: "RIGHT CYCLE FORMAT / MIDDLE CALENDAR"
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            Core.State.setClockFormat(ClockModel.nextFormat(root._format));
        } else if (root.panel) {
            root.panel.toggleFrom(root);
        }
    }
}

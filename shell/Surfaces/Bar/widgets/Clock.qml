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
// every other widget here). Left click toggles the calendar panel anchored
// under this cell, same panel-open accent dot idiom as Battery.qml. Right
// click cycles ClockModel's format ring (M26 Task 4) and persists the
// choice through Core.State, never settings.json (the shell only ever
// reads that file). Every ring entry renders through Qt.formatDateTime;
// the ISO-week preset substitutes its 'ww' token by hand first since Qt
// has no ISO-week specifier of its own.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    property date _now: new Date()

    readonly property string _format: Core.State.clockFormat !== "" ? Core.State.clockFormat : ClockModel.CLOCK_FORMATS[0]
    readonly property string _text: Qt.formatDateTime(root._now, ClockModel.substituteIsoWeek(root._format, root._now))

    standalone: true

    // The ring's presets differ wildly in width ("hh:mm" versus
    // "yyyy-MM-dd hh:mm") — glide the swap instead of shoving every other
    // right-region cell instantly (DESIGN.md §4, M16 Task 2's contract).
    Behavior on implicitWidth {
        NumberAnimation { duration: Core.Theme.motion.standard; easing.type: Core.Theme.motion.easing }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root._text
        color: root.foreground
        font.family: Core.Theme.fontFamily
        font.pixelSize: Core.Theme.fontSize.body
    }

    PanelOpenDot {
        visible: root._panelOpen
        inverted: root.invertedNow
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root._now = new Date()
    }

    interactive: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            Core.State.setClockFormat(ClockModel.nextFormat(root._format));
        } else if (root.panel) {
            root.panel.toggleFrom(root);
        }
    }
}

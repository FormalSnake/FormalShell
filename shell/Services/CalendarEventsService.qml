pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core
import "../Calendar/ics.js" as Ics

// Local .ics events for the calendar panel (M6 Task 5's spike outcome:
// EDS/GOA over D-Bus needs a persistent connection no CLI tool gives you
// one call at a time — see docs/spikes/2026-07-28-eds-calendar-events.md —
// so events come from a khal/vdir-style directory of .ics files instead).
// `calendar.icsDir` in settings.json points at it; unset (the default)
// means zero events, same honest-empty-state contract every other panel
// backend follows in the test VM.
//
// Reading is a flat `cat "$dir"/*.ics` (mirrors ThemeEngine's own
// drop-in-directory read) rather than any folder-watch model — Quickshell
// has no directory-listing QML type, and a periodic re-read is plenty for
// data that changes on the timescale of "someone edited a calendar file".
Singleton {
    id: root

    readonly property string icsDir: Core.Config.get("calendar.icsDir", "")
    readonly property bool available: root.icsDir !== ""
    property var events: []

    // Checks icsDir directly rather than through the `available` alias:
    // this runs from onIcsDirChanged, and reading a *different* property's
    // binding (available) that also depends on icsDir isn't guaranteed to
    // have re-evaluated yet at that exact point in the change cascade —
    // icsDir itself is already the fresh value by definition.
    function refresh() {
        if (root.icsDir === "") {
            root.events = [];
            return;
        }
        readProc.command = ["sh", "-c", 'for f in "$1"/*.ics; do [ -f "$f" ] && cat "$f" && printf "\\n"; done', "sh", root.icsDir];
        readProc.running = true;
    }

    // Events on a given local calendar date — the day-cell query
    // CalendarPanel makes once per visible day.
    function onDate(date) {
        return Ics.eventsOnDate(root.events, date);
    }

    // Config's settings.json load is async (FileView), so icsDir can still
    // be "" the instant this singleton completes — refresh off the
    // property actually changing rather than a single onCompleted shot, or
    // a settings.json that finishes loading a moment later never gets read
    // until the 5-minute timer below catches up.
    Component.onCompleted: root.refresh()
    onIcsDirChanged: root.refresh()

    Timer {
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: readProc

        stdout: StdioCollector {
            onStreamFinished: root.events = Ics.parseEvents(text)
        }
    }
}

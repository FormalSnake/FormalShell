pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core
import "../Calendar/ics.js" as Ics

// Calendar events for the calendar panel, from two coexisting backends
// merged by UID (Ics.mergeEvents):
//
// - Local .ics files: `calendar.icsDir` in settings.json points at a
//   khal/vdir-style directory (M6 Task 5's spike outcome). Reading is a
//   flat `cat "$dir"/*.ics` (mirrors ThemeEngine's own drop-in-directory
//   read) rather than any folder-watch model — Quickshell has no
//   directory-listing QML type, and a periodic re-read is plenty for data
//   that changes on the timescale of "someone edited a calendar file".
// - EDS/GOA over D-Bus via the `formalshell-eds` companion CLI (M12
//   Task 3): the spike's blocker was that EDS's whole
//   OpenCalendar -> Open -> GetObjectList handshake must run over one held
//   bus connection, which no chain of gdbus/busctl calls can provide — the
//   CLI does it in one process and prints raw ICS, fed through the exact
//   same parser. `calendar.eds` (bool, default true) gates it; the first
//   run doubles as the reachability probe, and a failure (nonzero exit, or
//   the binary never starting at all) degrades silently to ics-only for
//   the rest of the process's life — one console.warn, no error cell, no
//   retry storm.
//
// Both refresh on the same cadence: icsDir change, every 5 minutes, and
// CalendarPanel's own on-open call.
Singleton {
    id: root

    readonly property string icsDir: Core.Config.get("calendar.icsDir", "")
    readonly property bool edsEnabled: Core.Config.get("calendar.eds", true)
    readonly property bool available: root.icsDir !== "" || (root.edsEnabled && !root._edsUnavailable)
    property var events: []

    property var _icsEvents: []
    property var _edsEvents: []
    // Flips true at most once, on the first failed CLI run — never back.
    property bool _edsUnavailable: false
    // Same normal-completion-vs-never-started discrimination
    // CommandModule.qml documents: quickshell's Process never emits
    // `exited` for a command that failed to start (a missing binary), only
    // `runningChanged`.
    property bool _edsSawExit: false

    // Checks icsDir directly rather than through the `available` alias:
    // this runs from onIcsDirChanged, and reading a *different* property's
    // binding (available) that also depends on icsDir isn't guaranteed to
    // have re-evaluated yet at that exact point in the change cascade —
    // icsDir itself is already the fresh value by definition.
    function refresh() {
        if (root.icsDir === "") {
            root._icsEvents = [];
            root._merge();
        } else {
            readProc.command = ["sh", "-c", 'for f in "$1"/*.ics; do [ -f "$f" ] && cat "$f" && printf "\\n"; done', "sh", root.icsDir];
            readProc.running = true;
        }
        if (root.edsEnabled && !root._edsUnavailable && !edsProc.running) {
            root._edsSawExit = false;
            edsProc.running = true;
        } else if (!root.edsEnabled && root._edsEvents.length > 0) {
            root._edsEvents = [];
            root._merge();
        }
    }

    function _merge() {
        root.events = Ics.mergeEvents(root._icsEvents, root._edsEvents);
    }

    function _edsDown(reason) {
        if (!root._edsUnavailable) {
            root._edsUnavailable = true;
            console.warn("CalendarEventsService: " + reason + " — EDS events disabled, ics-only from here on");
        }
        if (root._edsEvents.length > 0) {
            root._edsEvents = [];
            root._merge();
        }
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
    onEdsEnabledChanged: root.refresh()

    Timer {
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: readProc

        stdout: StdioCollector {
            onStreamFinished: {
                root._icsEvents = Ics.parseEvents(text);
                root._merge();
            }
        }
    }

    Process {
        id: edsProc
        command: ["formalshell-eds", "events"]

        stdout: StdioCollector {
            id: edsCollector
        }
        onExited: exitCode => {
            root._edsSawExit = true;
            if (exitCode !== 0) {
                root._edsDown("formalshell-eds exited " + exitCode);
                return;
            }
            root._edsEvents = Ics.parseEvents(edsCollector.text);
            root._merge();
        }
        onRunningChanged: {
            if (!edsProc.running && !root._edsSawExit)
                root._edsDown("formalshell-eds failed to start");
        }
    }
}

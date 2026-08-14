pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Runtime-mutable session state (wallpaper, mode, dnd) — the shell owns and
// rewrites this file; settings.json stays read-only. Quickshell.statePath()
// resolves under quickshell/by-shell/<shellId>/, not the spec-mandated
// $XDG_STATE_HOME/formalshell/, so the path is built by hand instead.
Singleton {
    id: root

    property alias wallpaper: adapter.wallpaper
    property alias mode: adapter.mode
    property alias dnd: adapter.dnd
    property alias calendarBirthYear: adapter.calendarBirthYear
    property alias calendarLifeExpectancy: adapter.calendarLifeExpectancy
    property alias appLaunches: adapter.appLaunches
    property alias reminders: adapter.reminders
    property alias trayPinned: adapter.trayPinned
    property alias trayHidden: adapter.trayHidden

    function setWallpaper(path) {
        adapter.wallpaper = path;
        stateFile.writeAdapter();
    }

    function setMode(newMode) {
        adapter.mode = newMode;
        stateFile.writeAdapter();
    }

    function toggleMode() {
        root.setMode(root.mode === "dark" ? "light" : "dark");
    }

    function setDnd(on) {
        adapter.dnd = on;
        stateFile.writeAdapter();
    }

    // Both keys land in one write — the life-progress easter egg (Calendar
    // panel, M6 Task 4) always collects birth year then life expectancy as a
    // single flow, and a half-set pair (birth year alone) has no valid
    // lifeFraction() to render anyway.
    function setCalendarLifeProgress(birthYear, lifeExpectancy) {
        adapter.calendarBirthYear = birthYear;
        adapter.calendarLifeExpectancy = lifeExpectancy;
        stateFile.writeAdapter();
    }

    // The menu's app-launch ledger — [{ id, count, lastMs }], the shape
    // shell/Menu/frecency.js owns end to end. This file only stores it:
    // the caller passes the already-recorded array (Frecency.record()
    // returns a fresh one, which is also what makes the alias' change
    // signal fire), so no scoring logic leaks into Core.
    function setAppLaunches(entries) {
        adapter.appLaunches = entries;
        stateFile.writeAdapter();
    }

    // Pending reminders: [{ id, message, setAt, dueAt }], the shape
    // shell/Reminders/model.js owns end to end. Same contract as
    // setAppLaunches above: the caller passes the already-computed array and
    // this file only stores it.
    function setReminders(entries) {
        adapter.reminders = entries;
        stateFile.writeAdapter();
    }

    // The tray's Bartender buckets: two arrays of SNI ids, the shape
    // shell/Tray/model.js owns end to end. Both land in one write for the
    // same reason setCalendarLifeProgress does: every action the manage
    // popup offers moves an id between the two at once (pinning clears a
    // hide and vice versa; TrayService keeps them mutually exclusive), so a
    // half-written pair would persist a state no action can produce.
    function setTrayBuckets(pinned, hidden) {
        adapter.trayPinned = pinned;
        adapter.trayHidden = hidden;
        stateFile.writeAdapter();
    }

    readonly property string _stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/formalshell";
    }

    FileView {
        id: stateFile
        path: root._stateDir + "/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: adapter
            property string wallpaper: ""
            property string mode: "dark"
            property bool dnd: false
            property int calendarBirthYear: 0
            property int calendarLifeExpectancy: 0
            property var appLaunches: []
            property var reminders: []
            property var trayPinned: []
            property var trayHidden: []
        }
    }
}

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
    property alias barCollapsed: adapter.barCollapsed

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

    // Whether each bar region's chevron is currently collapsed (M24), keyed
    // by region name. Written by the chevron cell's own click and by `bar
    // chevron`, read by Bar.qml's region delegate. A region with no chevron
    // in bar.layout keeps a value here that nothing reads, which is what
    // makes adding the chevron back mid-session resume where it left off.
    // The object is replaced wholesale rather than mutated in place: a
    // JsonAdapter var property only notifies on assignment, so writing one
    // key of the existing object would persist without ever re-evaluating a
    // binding.
    function setBarCollapsed(region, collapsed) {
        var next = {};
        var current = adapter.barCollapsed;
        for (var key in current)
            next[key] = current[key];
        next[region] = collapsed;
        adapter.barCollapsed = next;
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
            // Collapsed is the default for every region, matching Hidden Bar
            // and Bartender: adding `chevron` to bar.layout has to visibly do
            // something on first run, or the widget reads as inert.
            property var barCollapsed: ({ left: true, center: true, right: true })
        }
    }
}

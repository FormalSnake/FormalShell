import Quickshell.Io

// `qs ipc call calendar select|status` — M13 Task 4's day-selection verbs,
// additive next to `panel open calendar` (which stays the summon path).
// select() takes a strict YYYY-MM-DD date, marks it as the panel's selected
// day and aligns the view month to it — the exact action clicking a day
// cell takes, exposed over IPC so the smoke rig can drive selection without
// depending on real pointer delivery into a layer surface (the same
// division picker's choose() and menu's select() already use). status()
// reports the selection state for headless assertion.
IpcHandler {
    target: "calendar"

    // Set from shell.qml — the single CalendarPanel instance.
    property var panel: null

    function select(date: string): string {
        if (!panel)
            return "error: calendar panel not ready";
        return panel.selectIsoDate(date) ? "ok" : "error: not a valid YYYY-MM-DD date: " + date;
    }

    function status(): string {
        if (!panel)
            return "error: calendar panel not ready";
        return JSON.stringify(panel.selectionStatus());
    }
}

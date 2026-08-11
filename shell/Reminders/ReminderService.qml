pragma Singleton
import QtQuick
import Quickshell
// `qs.Core as Core`, not a bare import: QtQuick already exports a type named
// State (for property-binding states). NotificationService.qml documents the
// same collision. Core.State disambiguates it.
import qs.Core as Core
import qs.Notifications
import "model.js" as Model

// Countdown reminders: set one with a duration and a message, get a
// notification when it comes due. model.js owns every rule (duration
// grammar, entry shape, the due split, all label formatting); this file is
// wiring only.
//
// Persistence is one-directional, the same shape as wallpaper/mode/dnd:
// Core.State.reminders (state.json) is the source of truth, every mutation
// here goes through Core.State.setReminders(), and the Connections block
// below mirrors it back into _pending. Nothing ever assigns _pending
// directly. That also makes state.json's async FileView load an ordinary
// case rather than a special one: whenever it lands, the mirror fires.
//
// Restart behaviour, decided rather than fallen into: a reminder whose due
// time passed while the shell was down fires on the first tick after
// state.json loads, because Model.due() treats an hours-old dueAt exactly
// like a just-crossed one. Firing late is honest; silently dropping it is
// not, and with durations running up to 30 days a reboot in the middle of
// one is ordinary rather than exotic.
//
// Urgency 2 on the fire path is load-bearing in two ways, only one of which
// is wanted. Notifications/model.js's bypassesDnd() lets an entry through
// DND only at urgency 2 AND with `local` set, which NotificationService.notify()
// stamps on everything it authors: that is the whole DND bypass, and a
// reminder the user explicitly asked for is exactly the case it exists for.
// The same urgency also forces expiresAt to 0 (model.js:65), so a fired
// reminder's toast is sticky until dismissed, and a user who ignores four of
// them hits MAX_POPUPS and sees the fifth land straight in the notification
// center instead of on screen. showSummary() uses urgency 1 precisely
// because a summary the user asked to see is neither critical nor worth
// making sticky.
Singleton {
    id: root

    // Mirror of Core.State.reminders, never the source of truth.
    property var _pending: []
    property int _serial: 0
    // double, not int: Date.now() is ~1.7e12 and silently truncates in an
    // int property.
    property double nowMs: 0

    readonly property var pending: root._pending
    readonly property int count: root._pending.length
    readonly property string barLabel: Model.barLabel(root._pending, root.nowMs)

    function _syncFromState() {
        root._pending = Model.normalize(Core.State.reminders);
        root.nowMs = Date.now();
    }

    Connections {
        target: Core.State
        function onRemindersChanged() { root._syncFromState(); }
    }

    // The signal above only covers changes: a singleton constructed after
    // state.json has already loaded would otherwise start empty.
    Component.onCompleted: root._syncFromState()

    function _append(seconds, message) {
        var text = String(message === undefined || message === null ? "" : message).trim();
        // Filled in at set time, so a stored entry always carries a real
        // message and the fire path needs no fallback branch of its own.
        if (text === "")
            text = Core.Config.get("reminders.defaultMessage", "Time's up");

        root._serial += 1;
        var entry = Model.makeEntry(seconds, text, Date.now(), root._serial);
        Core.State.setReminders(Model.add(root._pending, entry));
        return entry;
    }

    // Both setters return the stored entry, or null when the duration did
    // not parse. Callers report that failure themselves rather than getting
    // a silent no-op.
    function setFromParts(durationText, message) {
        var seconds = Model.parseDuration(durationText);
        return seconds === null ? null : root._append(seconds, message);
    }

    function setFromSpec(text) {
        var spec = Model.parseSpec(text);
        return spec === null ? null : root._append(spec.seconds, spec.message);
    }

    function clear() {
        var dropped = root._pending.length;
        if (dropped > 0)
            Core.State.setReminders([]);
        return dropped;
    }

    function showSummary() {
        if (root._pending.length === 0) {
            NotificationService.notify("Reminders", "None pending", 1);
            return;
        }
        NotificationService.notify("Reminders", Model.summaryLines(root._pending, Date.now()).join("\n"), 1);
    }

    function snapshot() {
        var now = Date.now();
        return root._pending.map(function (e) {
            var secs = Model.remainingSeconds(e, now);
            return {
                id: e.id,
                message: e.message,
                dueAt: e.dueAt,
                remainingSeconds: secs,
                remaining: Model.countdownLabel(secs)
            };
        });
    }

    // For callers holding an entry that render when it lands rather than a
    // countdown to it (the IPC reply, the menu's set confirmation), so
    // model.js stays the only place that formats a reminder.
    function dueClock(dueAtMs) {
        return Model.dueClock(dueAtMs);
    }

    // Answer to the menu's `reminder-set` input prompt. Wired from shell.qml
    // as a Connections on the Menu instance's selectionResolved signal, which
    // keeps the reference one-directional: nothing under Reminders/ knows a
    // Menu type exists.
    readonly property string inputToken: "reminder-set"

    function resolveInput(token, value, cancelled) {
        if (token !== root.inputToken)
            return;
        if (cancelled)
            return;

        var entry = root.setFromSpec(value);
        if (entry)
            NotificationService.notify("Reminder set", entry.message + " at " + Model.dueClock(entry.dueAt), 1);
        else
            NotificationService.notify("Reminder", "Could not read \"" + value + "\" as a duration", 1);
    }

    // Ticking nowMs is what re-renders the bar cell's countdown. The
    // Model.due() no-fire path returns the same `remaining` array identity it
    // was given, and this returns before touching Core.State on it, so an
    // idle countdown never rewrites state.json once a second.
    function _tick() {
        var now = Date.now();
        root.nowMs = now;

        var split = Model.due(root._pending, now);
        if (split.fired.length === 0)
            return;

        split.fired.forEach(function (e) {
            NotificationService.notify("Reminder", e.message, 2);
        });
        Core.State.setReminders(split.remaining);
    }

    Timer {
        interval: 1000
        repeat: true
        running: root._pending.length > 0
        onTriggered: root._tick()
    }
}

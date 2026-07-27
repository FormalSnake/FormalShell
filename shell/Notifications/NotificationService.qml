pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.Compositor
import "model.js" as Model

// Owns the freedesktop NotificationServer and drives model.js's pure
// three-tier reducer (M5 Task 3). Live Notification objects are kept OUT of
// the reducer state — model.js entries are plain JS data, retained after the
// server destroys the notification — in a side map keyed by id instead, so
// dismiss()/expire()/action-invoke can still reach the real object while it
// lives.
Singleton {
    id: root

    property var _state: Model.initialState()
    property var _live: ({})

    readonly property var popups: root._state.popups
    readonly property var pending: root._state.pending
    readonly property var past: root._state.past
    readonly property bool dnd: root._state.dnd

    function _findEntry(id) {
        return root.popups.find(e => e.id === id)
            ?? root.pending.find(e => e.id === id)
            ?? root.past.find(e => e.id === id)
            ?? null;
    }

    NotificationServer {
        id: server

        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notification => {
            // Without tracked = true the Notification is destroyed as soon as
            // this handler returns, taking the _live entry with it.
            notification.tracked = true;
            var id = notification.id;
            root._live[id] = notification;
            notification.closed.connect(function () {
                // Guard against replaces_id handing this slot to a newer
                // notification before the old one's closed signal lands.
                if (root._live[id] === notification)
                    delete root._live[id];
            });

            root._state = Model.add(root._state, {
                id: id,
                appName: notification.appName,
                appIcon: notification.appIcon,
                summary: notification.summary,
                body: notification.body,
                urgency: notification.urgency,
                actions: (notification.actions ?? []).map(a => ({ key: a.identifier, label: a.text })),
                image: notification.image || "",
                // Omarchy's rule (verified against basecamp/omarchy quattro's
                // NotificationLogic.js shouldBypassDnd): the literal CLI
                // default app_name, nothing inferred from urgency alone.
                senderIsNotifySend: notification.appName === "notify-send"
            }, Date.now(), {});
        }
    }

    // Popup lifetime: 1s tick moves timed-out popups to pending and hints
    // the sender that each one expired (dismissPopup below is the
    // user-initiated counterpart, which calls .dismiss() instead).
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            var before = root._state.popups.map(p => p.id);
            var next = Model.expire(root._state, Date.now());
            var stillPopup = {};
            next.popups.forEach(p => stillPopup[p.id] = true);
            before.forEach(id => {
                if (stillPopup[id]) return;
                var notif = root._live[id];
                if (notif) {
                    try {
                        notif.expire();
                    } catch (e) {}
                }
            });
            root._state = next;
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root._state = Model.prunePast(root._state, Date.now())
    }

    function dismissPopup(id) {
        root._state = Model.dismissPopup(root._state, id, Date.now());
        var notif = root._live[id];
        if (notif) {
            try {
                notif.dismiss();
            } catch (e) {}
        }
    }

    function invokeAction(id, key) {
        var notif = root._live[id];
        if (!notif)
            return;
        var actions = notif.actions ?? [];
        for (var i = 0; i < actions.length; i++) {
            if (actions[i].identifier === key) {
                actions[i].invoke();
                return;
            }
        }
    }

    // Click-to-jump fallback for senders with no "default" action (most chat
    // apps): match the entry's appName against a live window's appId,
    // case-insensitively, and focus it. No-op if nothing matches.
    function focusSender(id) {
        var entry = root._findEntry(id);
        var needle = entry ? String(entry.appName || "").toLowerCase() : "";
        if (!needle)
            return;
        var windows = CompositorService.windows ?? [];
        for (var i = 0; i < windows.length; i++) {
            if (String(windows[i].appId || "").toLowerCase() === needle) {
                CompositorService.focusWindow(windows[i].id);
                return;
            }
        }
    }

    function markAllSeen() {
        root._state = Model.markAllSeen(root._state, Date.now());
    }

    function dismissOne(id) {
        root._state = Model.dismissOne(root._state, id);
    }

    function dismissAll() {
        root._state = Model.dismissAll(root._state);
    }

    function clearPending() {
        root._state = Model.clearPending(root._state);
    }

    function setDnd(on) {
        root._state = Model.setDnd(root._state, on);
    }

    // Fires the most recent popup-or-pending entry's default action if it
    // has one, then dismisses it either way: a popup is archived to past
    // (dismissPopup's seen-and-keep contract), a pending entry is dropped
    // outright (dismissOne — it was never shown, there's nothing to archive
    // as "seen").
    function invokeLast() {
        var target = Model.invokeTarget(root._state);
        if (!target)
            return;
        if ((target.actions ?? []).some(a => a.key === "default"))
            root.invokeAction(target.id, "default");
        if (root._state.popups.some(p => p.id === target.id))
            root.dismissPopup(target.id);
        else
            root.dismissOne(target.id);
    }
}

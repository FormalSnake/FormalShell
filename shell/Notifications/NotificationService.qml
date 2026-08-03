pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.Compositor
// `qs.Core as Core`, not a bare import: QtQuick already exports a type named
// State (for property-binding states) — see ThemeEngine.qml's own note on
// this same collision. Core.State disambiguates it.
import qs.Core as Core
import "model.js" as Model

// Owns the freedesktop NotificationServer and drives model.js's pure
// three-tier reducer (M5 Task 3). Live Notification objects are kept OUT of
// the reducer state — model.js entries are plain JS data, retained after the
// server destroys the notification — in a side map keyed by id instead, so
// dismiss()/expire()/action-invoke can still reach the real object while it
// lives.
//
// DND persistence: Core.State.dnd (state.json) is the source of truth, same
// pattern as wallpaper/mode — setDnd() below only ever writes there, and the
// Connections block mirrors it into the reducer's own state.dnd (needed by
// model.js's add() bypass check) whenever it changes, including the async
// FileView load completing after this singleton's _state has already
// initialized with the compile-time default.
Singleton {
    id: root

    property var _state: Model.initialState()
    property var _live: ({})
    // Ids currently mid-flight through a dismiss()/expire() call WE made
    // (dismissPopup, the expiry timer): the model was already updated
    // before that call, so the closed() it triggers must be a no-op there.
    // Anything closed WITHOUT this flag set — CloseNotification from the
    // sender, an action's implicit close, a generation switch — never
    // touched the model at all and must be dropped from it here.
    property var _selfClosing: ({})
    // Popup ids currently under the pointer (Toasts.qml's NotificationCard
    // hover -> setPopupHovered below): the 1s expiry Timer pushes these
    // ids' expiresAt forward by its own tick instead of letting
    // Model.expire see them cross 0, so hovering pauses a toast's
    // countdown (omarchy's !card.hovered gate) without model.js needing any
    // hover concept of its own.
    property var _hoveredPopups: ({})

    // Omarchy's duration bands (low 5s / normal 8s / cap 30s), honoring a
    // sender's own expireTimeout hint (freedesktop spec: milliseconds,
    // <=0 meaning "use the server default") when it falls inside the band.
    // Critical is sticky regardless — Model.add()/update() already force
    // expiresAt to 0 for urgency 2, so the value returned here for
    // critical is never actually consulted.
    readonly property int _lowPopupDurationMs: 5000
    readonly property int _normalPopupDurationMs: 8000
    readonly property int _maxPopupDurationMs: 30000

    function _requestedDurationMs(expireTimeout) {
        var ms = Number(expireTimeout || 0);
        return (isFinite(ms) && ms > 0) ? Math.round(ms) : 0;
    }

    function _timeoutMsFor(urgency, expireTimeout) {
        var requested = root._requestedDurationMs(expireTimeout);
        var floor = urgency === 0 ? root._lowPopupDurationMs : root._normalPopupDurationMs;
        return Math.min(root._maxPopupDurationMs, Math.max(floor, requested));
    }

    function setPopupHovered(id, hovered) {
        if (hovered)
            root._hoveredPopups[id] = true;
        else
            delete root._hoveredPopups[id];
    }

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

            // server.cpp's Notify() honours replaces_id by mutating this same
            // Notification object in place (updateProperties) rather than
            // emitting a new `notification` — this handler runs exactly
            // once per id, and every subsequent replace only fires the
            // per-property NOTIFY signals below. Resync the model entry
            // from the live object on each one so replaces_id senders
            // (progress bars, "Song A" -> "Song B") actually update instead
            // of freezing the first-arrival snapshot.
            function syncFromLive() {
                if (root._live[id] !== notification)
                    return;
                root._state = Model.update(root._state, id, {
                    appName: notification.appName,
                    appIcon: notification.appIcon,
                    summary: notification.summary,
                    body: notification.body,
                    urgency: notification.urgency,
                    actions: (notification.actions ?? []).map(a => ({ key: a.identifier, label: a.text })),
                    image: notification.image || "",
                    senderIsNotifySend: notification.appName === "notify-send"
                }, Date.now());
            }
            notification.appNameChanged.connect(syncFromLive);
            notification.appIconChanged.connect(syncFromLive);
            notification.summaryChanged.connect(syncFromLive);
            notification.bodyChanged.connect(syncFromLive);
            notification.urgencyChanged.connect(syncFromLive);
            notification.actionsChanged.connect(syncFromLive);
            notification.imageChanged.connect(syncFromLive);

            notification.closed.connect(function () {
                // Guard against replaces_id handing this slot to a newer
                // notification before the old one's closed signal lands.
                if (root._live[id] === notification)
                    delete root._live[id];

                if (root._selfClosing[id]) {
                    delete root._selfClosing[id];
                    return;
                }
                // Sender-initiated close (CloseNotification) or an action's
                // implicit close on a non-resident notification: the model
                // was never told, so it would otherwise sit in popups/pending
                // forever — sticky critical ones with no other way out.
                root._state = Model.dismissOne(root._state, id);
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
            }, Date.now(), {
                timeoutMs: root._timeoutMsFor(notification.urgency, notification.expireTimeout)
            });
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
            // Pause-on-hover: push every hovered, non-sticky popup's
            // expiresAt out by this tick's own interval before Model.expire
            // ever sees it, so the countdown holds for as long as the
            // pointer stays over the card. model.js has no hover concept;
            // this is a plain reassignment of the same shape Model.add()
            // itself returns.
            if (Object.keys(root._hoveredPopups).length > 0) {
                var pushed = root._state.popups.map(p => {
                    if (p.expiresAt !== 0 && root._hoveredPopups[p.id])
                        return Object.assign({}, p, { expiresAt: p.expiresAt + 1000 });
                    return p;
                });
                root._state = Object.assign({}, root._state, { popups: pushed });
            }

            var before = root._state.popups.map(p => p.id);
            var next = Model.expire(root._state, Date.now());
            var stillPopup = {};
            next.popups.forEach(p => stillPopup[p.id] = true);
            before.forEach(id => {
                if (stillPopup[id]) return;
                delete root._hoveredPopups[id];
                var notif = root._live[id];
                if (notif) {
                    root._selfClosing[id] = true;
                    try {
                        notif.expire();
                    } catch (e) {
                        delete root._selfClosing[id];
                    }
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
        delete root._hoveredPopups[id];
        root._state = Model.dismissPopup(root._state, id, Date.now());
        var notif = root._live[id];
        if (notif) {
            root._selfClosing[id] = true;
            try {
                notif.dismiss();
            } catch (e) {
                delete root._selfClosing[id];
            }
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
        Core.State.setDnd(on);
    }

    Connections {
        target: Core.State
        function onDndChanged() { root._state = Model.setDnd(root._state, Core.State.dnd); }
    }

    // Shell-authored notifications (ScreenshotIpc's saved/failed feedback):
    // feed the reducer directly with a shell-local string id. The server
    // path is unusable from inside the process that owns the bus name, and
    // round-tripping through notify-send would add a binary dependency for
    // no isolation gain. String ids can't collide with the server's uint
    // ids; every _live[] lookup simply misses, which each caller already
    // guards.
    property int _localSerial: 0

    function notify(summary, body) {
        root._localSerial += 1;
        root._state = Model.add(root._state, {
            id: "local-" + root._localSerial,
            appName: "formalshell",
            appIcon: "",
            summary: summary,
            body: body,
            urgency: 1,
            actions: [],
            image: "",
            senderIsNotifySend: false
        }, Date.now(), {});
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

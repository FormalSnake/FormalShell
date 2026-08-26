pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.Compositor
// `qs.Core as Core`, not a bare import: QtQuick already exports a type named
// State (for property-binding states), see ThemeEngine.qml's own note on
// this same collision. Core.State disambiguates it.
import qs.Core as Core
import "model.js" as Model

// Owns the freedesktop NotificationServer and drives model.js's pure
// three-tier reducer (M5 Task 3). Live Notification objects are kept OUT of
// the reducer state, model.js entries are plain JS data, retained after the
// server destroys the notification, in a side map keyed by id instead, so
// dismiss()/expire()/action-invoke can still reach the real object while it
// lives.
//
// DND persistence: Core.State.dnd (state.json) is the source of truth, same
// pattern as wallpaper/mode, setDnd() below only ever writes there, and the
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
    // Anything closed WITHOUT this flag set, CloseNotification from the
    // sender, an action's implicit close, a generation switch, never
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
    // Critical is sticky regardless, Model.add()/update() already force
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

    // Takes the group's whole `memberIds` array, not one id: identical
    // notifications collapse into a single card (Model.groupEntries), so the
    // pointer sits over every member at once and each one's expiry has to be
    // held. A bare id here would stringify the array into a key that matches
    // nothing, leaving a hovered group counting down.
    function setPopupHovered(memberIds, hovered) {
        var ids = memberIds ?? [];
        for (var i = 0; i < ids.length; i++) {
            if (hovered)
                root._hoveredPopups[ids[i]] = true;
            else
                delete root._hoveredPopups[ids[i]];
        }
    }

    // Written by the single Center instance (Surfaces/Notifications/Center.qml)
    // so surfaces that never get a handle on it can still see it. Toasts.qml
    // already suppresses its own stack while the center is up, and Tooltip.qml
    // needs the same fact: the center is a Top-layer card anchored top-right
    // under the bar, exactly where a tooltip for a right-region cell lands, but
    // it is not a Panel so it never registers with PanelRegistry.
    property bool centerOpen: false

    // Sonner-style stack force-expand (M34 Task 2), set only by the
    // `notifications expand` IPC verb, the rig has no synthetic pointer,
    // so this is the IPC stand-in for "hover the stack" (the bar
    // chevron's own `expand` verb is the named precedent for this shape).
    // Each Toasts.qml instance ORs this with its own local hover, and it
    // is deliberately session-only (not Core.State/state.json): unlike the
    // chevron's collapsed flag, this changes on every hover-enter/leave
    // and has no business surviving a restart.
    property bool stackExpanded: false

    function setStackExpanded(on) {
        root.stackExpanded = on;
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
        // false (the default, spelled out here since it's load-bearing):
        // styledBody() in model.js escapes `&`/`<`/`>` on the assumption
        // that senders were truthfully told markup isn't safe to send and
        // may include those characters incidentally. Flipping this to true
        // without also parsing/whitelisting real sender markup would be a
        // lie the escaping then contradicts.
        bodyMarkupSupported: false
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
            // emitting a new `notification`, this handler runs exactly
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
                    desktopEntry: notification.desktopEntry || "",
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
            notification.desktopEntryChanged.connect(syncFromLive);
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
                // forever, sticky critical ones with no other way out.
                root._state = Model.dismissOne(root._state, id);
            });

            root._state = Model.add(root._state, {
                id: id,
                appName: notification.appName,
                appIcon: notification.appIcon,
                desktopEntry: notification.desktopEntry || "",
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

    // Dismissing one grouped card must close every notification behind it,
    // including each sender's own live server object, or the members that
    // were not the group's representative survive into the next tick and the
    // card reappears with a smaller count.
    function dismissPopupGroup(memberIds) {
        var ids = memberIds ?? [];
        for (var i = 0; i < ids.length; i++)
            root.dismissPopup(ids[i]);
    }

    function invokeAction(id, key) {
        // Shell-authored entries have no live server object to invoke through
        // (see notify() below), so their callbacks are held here and routed
        // first. One entry point for both origins: the toast and the center
        // must not need to know which kind of notification they are showing.
        var local = root._localActions[id];
        if (local && local[key]) {
            local[key]();
            return;
        }
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

    // The center's counterpart to dismissPopupGroup: drops every member
    // outright rather than archiving it, matching dismissOne's own contract
    // for a row the user closed from the history surface.
    function dismissGroup(memberIds) {
        var ids = memberIds ?? [];
        for (var i = 0; i < ids.length; i++)
            root._state = Model.dismissOne(root._state, ids[i]);
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

    // Callbacks for shell-authored actions, keyed by local id then action key.
    // The reducer only ever stores the serializable {key, label} pair, so the
    // functions cannot ride along in the state object.
    property var _localActions: ({})

    // urgency defaults to normal (1); pass 2 for a critical local warning
    // (M16 Task 5's low-battery path), Model.add() already makes those
    // sticky and model.js's bypassesDnd() already lets a `local` entry
    // through DND on its own honest marker, same as a real notify-send
    // critical.
    //
    // `actions` is an optional [{ key, label, invoke }]; `image` an optional
    // path rendered as the entry's thumbnail (the capture flow's saved PNG).
    function notify(summary, body, urgency, actions, image) {
        urgency = urgency === undefined ? 1 : urgency;
        root._localSerial += 1;
        var id = "local-" + root._localSerial;
        var list = actions ?? [];

        if (list.length > 0) {
            var callbacks = {};
            list.forEach(function (a) { callbacks[a.key] = a.invoke; });
            root._localActions[id] = callbacks;
        }

        root._state = Model.add(root._state, {
            id: id,
            appName: "formalshell",
            appIcon: "",
            summary: summary,
            body: body,
            urgency: urgency,
            actions: list.map(a => ({ key: a.key, label: a.label })),
            image: image ?? "",
            senderIsNotifySend: false,
            local: true
        }, Date.now(), {});
    }

    // Callbacks outlive the reducer entry otherwise: a long session firing
    // capture notifications would accumulate one closure per shot, each
    // pinning the path string it captured. Pruned against all three tiers
    // rather than on dismiss, because an entry archived to `past` is still
    // in the center with its action still live.
    function _pruneLocalActions() {
        var ids = root._localActions;
        if (Object.keys(ids).length === 0)
            return;
        var alive = {};
        [root._state.popups, root._state.pending, root._state.past].forEach(function (tier) {
            tier.forEach(function (entry) { alive[entry.id] = true; });
        });
        Object.keys(ids).forEach(function (id) {
            if (!alive[id])
                delete ids[id];
        });
    }

    on_StateChanged: root._pruneLocalActions()

    // Fires the most recent popup-or-pending entry's default action if it
    // has one, then dismisses it either way: a popup is archived to past
    // (dismissPopup's seen-and-keep contract), a pending entry is dropped
    // outright (dismissOne, it was never shown, there's nothing to archive
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

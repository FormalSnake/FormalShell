import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components
import qs.Notifications
import "../../Notifications/model.js" as Model

// The notification history center (DESIGN.md §Notifications, M5 Task 5,
// M8b Task 5): summonable, right-anchored, full height below the bar — the
// ASCII-OS table surface (DESIGN.md §2), unlike Toasts.qml's individually
// carded popups: rows share rules, and both the DND toggle and every
// notification row invert to the accent pair on hover (§2.2's "a
// highlighted notification-center row inverts") via `selected`,
// not the plain hover-tint the shared NotificationCard otherwise defaults
// to (`invertOnHover: true` below opts these rows into it). Two ledger
// sections — PENDING (unseen) then EARLIER (seen, rolling 15min TTL) —
// share NotificationCard with Toasts.qml's popup stack; only the dismiss
// wiring differs (dismissGroup here drops outright, dismissPopupGroup there
// archives to past — see NotificationService's own doc comment on the
// distinction). Both sections collapse identical repeats into one counted
// row the same way the toast stack does, so a repeat that expired out of a
// group re-groups here instead of reappearing as separate rows. DND is the
// top cell, an accent-filled block per DESIGN's "active toggle cell" rule
// when armed (Cell's own paint priority keeps that fill on top of the
// hover-inversion below); unarmed, hovering it
// inverts like any other row. The center never lists live popups, only what has left
// that tier — Toasts.qml suppresses its own overlay stack for as long as
// this surface is open, so a sticky critical popup can't sit on top of it
// (see Toasts's own header comment).
PanelWindow {
    id: root

    property bool isOpen: false

    // Mirrored onto the service so surfaces with no handle on this instance can
    // see it — see NotificationService.centerOpen's own comment.
    onIsOpenChanged: NotificationService.centerOpen = root.isOpen

    // Bar.qml publishes its content-derived height as Theme.barHeight (the
    // same lookup Panel.qml uses). The old hardcoded-32 mirror predated
    // that: once the bar grew past 32px it left this surface overlapping
    // the bar's bottom rows, covering the bell cell's center-open accent
    // dot (found pixel-checking M13b Task 2's smoke screenshots).
    readonly property int _barHeight: Theme.barHeight

    readonly property var _screen: {
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    // Newest-first: history reads top-down like everything else here. Left
    // ungrouped: clearAll() below sweeps the raw tier, and Model.groupEntries
    // preserves whichever direction it is handed, so the rows below group
    // this list newest-first with each group sitting where its newest member
    // was.
    readonly property var _pastNewestFirst: NotificationService.past.slice().reverse()

    // Section counts stay on the raw tiers: those are the real notification
    // counts, and each row's own trailing count names its collapse.
    readonly property var _pendingRows: Model.groupEntries(NotificationService.pending)
    readonly property var _pastRows: Model.groupEntries(root._pastNewestFirst)

    function open() {
        root.isOpen = true;
    }

    // Marking pending seen happens on close, not open, so the PENDING
    // section's unseen count stays accurate for as long as the user is
    // actually looking at it. No-op if already closed (mirrors Menu.qml's
    // _abandonPendingSelect guard) so a redundant close() never re-seens
    // entries that arrived after the real close already ran.
    function close() {
        if (!root.isOpen) return;
        root.isOpen = false;
        NotificationService.markAllSeen();
    }

    // Composed entirely from existing service verbs (M15 Task 2's produces
    // list is explicit that this shouldn't need a new one): clearPending()
    // already drops the whole tier, and dismissOne() already generalizes
    // across tiers, so sweeping past with it needs nothing model.js doesn't
    // already expose. Popups are Toasts.qml's own surface and untouched
    // here, same as the DND toggle only ever governing what lands here.
    function clearAll() {
        NotificationService.clearPending();
        NotificationService.past.forEach(e => NotificationService.dismissOne(e.id));
    }

    // Relative timestamps ("2m ago") only ever recompute off this timer per
    // the plan-wide constraint — never off the reducer's own 1s tick.
    property double _now: Date.now()
    Timer {
        interval: 30000
        running: root.isOpen
        repeat: true
        onTriggered: root._now = Date.now()
    }

    screen: root._screen
    // Held visible through the exit fade (DESIGN.md §4): close() drops
    // isOpen, card's opacity Behavior runs to 0, then the window unmaps.
    // The window itself is transparent so the fade covers the whole card —
    // card paints its own background below.
    visible: root.isOpen || card.opacity > 0
    color: "transparent"
    implicitWidth: Theme.space.popupWidthWide

    WlrLayershell.namespace: "formalshell:notifications-center"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors { top: true; right: true; bottom: true }
    margins.top: root._barHeight

    // Enter/exit (DESIGN.md §4): the whole card fades and slides in from
    // the right edge (this surface is right-anchored), one animated scalar
    // so a reopen mid-exit reverses in place.
    Item {
        id: card
        anchors.fill: parent
        opacity: root.isOpen ? 1 : 0
        transform: Translate { x: (1 - card.opacity) * Theme.motion.slide }

        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.color.background
        }

        // The card's own border ring on all four sides (DESIGN.md's omarchy
        // card chrome, §1.3's card-gutter split): this is a summoned list
        // surface, so rows inset by `popupPadding` — the same gutter
        // Menu.qml's card uses, not `panelPadding` — instead of the old
        // borderWidth-only inset that sat rows ~2px from the edge. Rows
        // still draw their own bottom+right per Cell's shared-rule contract;
        // the eraser rectangle below papers over the trailing right-edge
        // hairline that would otherwise double the frame's own right rule
        // `popupPadding` apart (same technique as Panel.qml/Menu.qml). No
        // bottom eraser: unlike those two cards, which wrap tightly to their
        // own content height, this surface's height is fixed to the screen,
        // so the last row's own bottom rule essentially never lands flush
        // with the frame's bottom rule.
        Rectangle {
            id: topRule
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.borderWidth
            color: Theme.color.rule
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Theme.borderWidth
            color: Theme.color.rule
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: Theme.borderWidth
            color: Theme.color.rule
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Theme.borderWidth
            color: Theme.color.rule
        }

        CardTitleBar {
            id: titleCell
            title: "NOTIFICATIONS"
            anchors.top: topRule.bottom
            anchors.topMargin: Theme.space.popupPadding
            anchors.left: parent.left
            anchors.leftMargin: Theme.borderWidth + Theme.space.popupPadding
            anchors.right: parent.right
            anchors.rightMargin: Theme.borderWidth + Theme.space.popupPadding

            // Bare-label actions (DESIGN.md §1.1's 2026-08-09 amendment): no
            // cell chrome, hover promotes ink foregroundDim -> foreground
            // instead of a fill/inversion. DND still needs to read as armed
            // at a glance now that it has no fill of its own to go accent —
            // its resting ink promotes straight to `accent` while armed,
            // the bare-label equivalent of the full-bleed accent cell this
            // replaced.
            MetaLabel {
                text: "DND"
                color: NotificationService.dnd
                    ? Theme.color.accent
                    : (dndHover.containsMouse ? Theme.color.foreground : Theme.color.foregroundDim)

                MouseArea {
                    id: dndHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.setDnd(!NotificationService.dnd)
                }
            }

            MetaLabel {
                text: "CLEAR ALL"
                color: clearAllHover.containsMouse ? Theme.color.foreground : Theme.color.foregroundDim

                MouseArea {
                    id: clearAllHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.clearAll()
                }
            }
        }

        Flickable {
            id: rowsFlickable
            anchors.top: titleCell.bottom
            anchors.left: parent.left
            anchors.leftMargin: Theme.borderWidth + Theme.space.popupPadding
            anchors.right: parent.right
            anchors.rightMargin: Theme.borderWidth + Theme.space.popupPadding
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.borderWidth + Theme.space.popupPadding
            clip: true
            contentWidth: width
            contentHeight: column.implicitHeight

            Column {
                id: column
                width: parent.width

                Cell {
                    visible: NotificationService.pending.length === 0 && NotificationService.past.length === 0
                    width: parent.width

                    MetaLabel {
                        text: "NO NOTIFICATIONS"
                    }
                }

                Cell {
                    visible: NotificationService.pending.length > 0
                    width: parent.width

                    MetaLabel {
                        text: "PENDING / " + NotificationService.pending.length
                        colon: false
                    }
                }

                Repeater {
                    model: root._pendingRows

                    delegate: NotificationCard {
                        id: pendingCard
                        required property var modelData

                        entry: pendingCard.modelData
                        now: root._now
                        width: parent.width
                        invertOnHover: true
                        pending: true

                        onDismiss: NotificationService.dismissGroup(pendingCard.modelData.memberIds)
                        onBodyClicked: {
                            if (pendingCard.modelData.actions.some(a => a.key === "default"))
                                NotificationService.invokeAction(pendingCard.modelData.id, "default");
                            else
                                NotificationService.focusSender(pendingCard.modelData.id);
                        }
                        onActionInvoked: key => NotificationService.invokeAction(pendingCard.modelData.id, key)
                    }
                }

                Cell {
                    visible: NotificationService.past.length > 0
                    width: parent.width

                    MetaLabel {
                        text: "EARLIER / " + NotificationService.past.length
                        colon: false
                    }
                }

                Repeater {
                    model: root._pastRows

                    delegate: NotificationCard {
                        id: pastCard
                        required property var modelData

                        entry: pastCard.modelData
                        now: root._now
                        width: parent.width
                        invertOnHover: true

                        onDismiss: NotificationService.dismissGroup(pastCard.modelData.memberIds)
                        onBodyClicked: {
                            if (pastCard.modelData.actions.some(a => a.key === "default"))
                                NotificationService.invokeAction(pastCard.modelData.id, "default");
                            else
                                NotificationService.focusSender(pastCard.modelData.id);
                        }
                        onActionInvoked: key => NotificationService.invokeAction(pastCard.modelData.id, key)
                    }
                }
            }
        }

        // Erases the trailing hairline every row (and titleCell itself)
        // draws along its own right edge (Cell's shared-rule contract) —
        // without this, that continuous line and the frame's own right
        // rule above would read as two parallel borders `popupPadding`
        // apart (same technique as Panel.qml/Menu.qml).
        Rectangle {
            anchors.top: titleCell.top
            anchors.right: rowsFlickable.right
            anchors.bottom: rowsFlickable.bottom
            width: Theme.borderWidth
            color: Theme.color.background
        }

        // Dog-ear fold mark (DESIGN.md §2 item 7).
        DogEar {}
    }

    // Multi-monitor dismiss (M16 Task 7): a click on another screen closes
    // the center exactly like the bell toggle does.
    DismissTwins {
        active: root.isOpen
        ownScreen: root.screen
        onDismissed: root.close()
    }
}

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components
import qs.Notifications

// The notification history center (DESIGN.md §Notifications, M5 Task 5,
// M8b Task 5): summonable, right-anchored, full height below the bar — the
// ASCII-OS table surface (DESIGN.md §2), unlike Toasts.qml's individually
// carded popups: rows share rules, and both the DND toggle and every
// notification row invert fg/bg on hover (§2.2's "a highlighted
// notification-center row swaps foreground/background") via `selected`,
// not the plain hover-tint the shared NotificationCard otherwise defaults
// to (`invertOnHover: true` below opts these rows into it). Two ledger
// sections — PENDING (unseen) then EARLIER (seen, rolling 15min TTL) —
// share NotificationCard with Toasts.qml's popup stack; only the dismiss
// wiring differs (dismissOne here drops outright, dismissPopup there
// archives to past — see NotificationService's own doc comment on the
// distinction). DND is the top cell, an accent-filled block per DESIGN's
// "active toggle cell" rule when armed (Cell's own paint priority keeps
// that fill on top of the hover-inversion below); unarmed, hovering it
// inverts like any other row. The center never lists live popups, only what has left
// that tier — Toasts.qml suppresses its own overlay stack for as long as
// this surface is open, so a sticky critical popup can't sit on top of it
// (see Toasts's own header comment).
PanelWindow {
    id: root

    property bool isOpen: false

    // Bar.qml's implicitHeight is a bare literal (32), not a shared Theme
    // token — mirrored here (same as Toasts.qml) so the center starts
    // exactly at its bottom edge.
    readonly property int _barHeight: 32

    readonly property var _screen: {
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    // Newest-first: history reads top-down like everything else here.
    readonly property var _pastNewestFirst: NotificationService.past.slice().reverse()

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
    visible: root.isOpen
    color: Theme.color.background
    implicitWidth: 420

    WlrLayershell.namespace: "formalshell:notifications-center"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors { top: true; right: true; bottom: true }
    margins.top: root._barHeight

    // Outer top/left rule — Cell.qml's shared-rule contract makes every cell
    // draw its own bottom+right rule, so the container only needs to close
    // off the top and left of the whole grid.
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

    Flickable {
        anchors.top: topRule.bottom
        anchors.left: parent.left
        anchors.leftMargin: Theme.borderWidth
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight

        Column {
            id: column
            width: parent.width

            Cell {
                id: dndCell
                width: parent.width
                accent: NotificationService.dnd
                selected: dndHover.containsMouse

                Text {
                    text: "DND"
                    color: dndCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.fontSize.body
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1
                }

                MouseArea {
                    id: dndHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.setDnd(!NotificationService.dnd)
                }
            }

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
                }
            }

            Repeater {
                model: NotificationService.pending

                delegate: NotificationCard {
                    id: pendingCard
                    required property var modelData

                    entry: pendingCard.modelData
                    now: root._now
                    width: parent.width
                    invertOnHover: true

                    onDismiss: NotificationService.dismissOne(pendingCard.modelData.id)
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
                }
            }

            Repeater {
                model: root._pastNewestFirst

                delegate: NotificationCard {
                    id: pastCard
                    required property var modelData

                    entry: pastCard.modelData
                    now: root._now
                    width: parent.width
                    invertOnHover: true

                    onDismiss: NotificationService.dismissOne(pastCard.modelData.id)
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
}

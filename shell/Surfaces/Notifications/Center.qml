import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components
import qs.Notifications
import "../../Notifications/model.js" as Model
import "../../Components/cursor.js" as Cursor

// The notification history centre (DESIGN.md §3, spec "Notification
// centre", M44 D3): shadcn's sheet, right-anchored and full height below the
// bar, `popupWidthWide`, drawn as a `Card` that keeps only its left border.
// Header: the title, a `Switch` for DND, a ghost `Clear all`. Two sections,
// PENDING (unseen) then SEEN (seen, rolling 15min TTL), sharing
// NotificationCard with Toasts.qml's popup stack. Only the dismiss wiring
// differs: dismissGroup here drops outright, dismissPopupGroup there
// archives to past (see NotificationService's own doc comment on the
// distinction). Both sections collapse identical repeats into one counted
// row the same way the toast stack does, so a repeat that expired out of a
// group re-groups here instead of reappearing as separate rows.
//
// The centre never lists live popups, only what has left that tier.
// Toasts.qml suppresses its own overlay stack for as long as this surface is
// open, so a sticky critical popup can't sit on top of it (see Toasts's own
// header comment).
PanelWindow {
    id: root

    property bool isOpen: false

    // Mirrored onto the service so surfaces with no handle on this instance can
    // see it, see NotificationService.centerOpen's own comment.
    onIsOpenChanged: NotificationService.centerOpen = root.isOpen

    // Bar.qml publishes its content-derived height as Theme.barHeight (the
    // same lookup Panel.qml uses).
    readonly property int _barHeight: Theme.barHeight

    // Set when the bell cell opened this (openFrom below), for the same reason
    // Panel.qml carries one: the bar cell you clicked names its own output,
    // and clicking a layer surface need not move keyboard focus there at all.
    // Null (every IPC and menu-route open) falls back to the focused output.
    property var anchorScreen: null

    readonly property var _screen: {
        if (root.anchorScreen) return root.anchorScreen;
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
    readonly property var _seenRows: Model.groupEntries(root._pastNewestFirst)

    // One flat cursor over both sections, pending first, so Up/Down walk the
    // card the way the eye reads it.
    readonly property var _rows: root._pendingRows.concat(root._seenRows)

    // --- Keyboard (spec "Keyboard model") --------------------------------
    //
    // Section 0 is the row list, 1 the DND switch, 2 `Clear all`; Tab walks
    // them. The maths is Panel.qml's, from cursor.js.
    property int cursorIndex: 0
    property bool cursorActive: false
    property int cursorSection: 0
    readonly property int _sectionCount: 3
    property bool _focusPrimed: false

    function moveCursor(dx, dy) {
        var next = Cursor.move(root.cursorIndex, root._rows.length, root.cursorActive, dx, dy, 1);
        root.cursorIndex = next.index;
        root.cursorActive = next.active;
        root.cursorSection = 0;
    }

    function activateCursor() {
        if (root.cursorSection === 1) {
            root.toggleDnd();
            return;
        }
        if (root.cursorSection === 2) {
            root.clearAll();
            return;
        }
        var index = Cursor.activation(root.cursorIndex, root._rows.length, root.cursorActive, 0);
        if (index >= 0)
            root.activateRow(root._rows[index]);
    }

    function deleteCursor() {
        if (root.cursorSection !== 0)
            return;
        var index = Cursor.activation(root.cursorIndex, root._rows.length, root.cursorActive, 0);
        if (index >= 0)
            NotificationService.dismissGroup(root._rows[index].memberIds);
    }

    function moveSection(direction) {
        root.cursorSection = Cursor.section(root.cursorSection, root._sectionCount, direction);
        root.cursorActive = true;
    }

    function toggleDnd() {
        NotificationService.setDnd(!NotificationService.dnd);
    }

    // Both the pointer and Enter land here: the entry's own default action if
    // it declared one, otherwise a jump to whatever window the sender owns.
    function activateRow(entry) {
        if (!entry)
            return;
        if (entry.actions.some(a => a.key === "default"))
            NotificationService.invokeAction(entry.id, "default");
        else
            NotificationService.focusSender(entry.id);
    }

    function open(screen) {
        root.anchorScreen = screen !== undefined ? screen : null;
        root.isOpen = true;
        root.cursorActive = false;
        root.cursorSection = 0;
        root._focusPrimed = false;
        root._beginFocusPrime();
        Qt.callLater(function () { backdrop.forceActiveFocus(); });
    }

    // Panel.qml's openFrom, for the one surface here that isn't a Panel: the
    // bell cell's own window names the output this card belongs on.
    function openFrom(item) {
        var window = item ? item.QsWindow.window : null;
        root.open(window ? window.screen : null);
    }

    // Marking pending seen happens on close, not open, so the PENDING
    // section's unseen count stays accurate for as long as the user is
    // actually looking at it. No-op if already closed (mirrors Menu.qml's
    // _abandonPendingSelect guard) so a redundant close() never re-seens
    // entries that arrived after the real close already ran.
    function close() {
        if (!root.isOpen) return;
        root.isOpen = false;
        root.cursorActive = false;
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
    // the plan-wide constraint, never off the reducer's own 1s tick.
    property double _now: Date.now()
    Timer {
        interval: 30000
        running: root.isOpen
        repeat: true
        onTriggered: root._now = Date.now()
    }

    readonly property int cardWidth: Theme.space.popupWidthWide

    // A Rectangle rounds all four corners, and this card sits flush against
    // both the screen's right edge and its bottom. Running it one radius past
    // each leaves the compositor to clip the three corners that would
    // otherwise round into the desktop, and leaves the top-left one, the only
    // corner actually inside the screen, rounded.
    readonly property int _overhang: Theme.radiusXl

    screen: root._screen
    // Held visible through the exit fade (spec "Motion"): close() drops
    // isOpen, the card's opacity Behavior runs to 0, then the window unmaps.
    // The window itself is transparent so the fade covers the whole card.
    visible: root.isOpen || frame.opacity > 0
    color: "transparent"

    WlrLayershell.namespace: "formalshell:notifications-center"
    WlrLayershell.layer: WlrLayer.Top
    // Keyboard focus follows isOpen, never `visible`. OnDemand alone never
    // takes focus for a surface summoned over IPC (wlroots waits for the
    // compositor to route it there, i.e. for a click), so every open()
    // primes with Exclusive and settles back once that focus has landed.
    // Panel.qml carries the full rationale, including why the prime has to
    // stay short under Hyprland.
    WlrLayershell.keyboardFocus: root.isOpen
        ? (root._focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
        : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1

    onBackingWindowVisibleChanged: root._beginFocusPrime()

    function _beginFocusPrime() {
        if (root.isOpen && root.backingWindowVisible)
            focusPrimeTimer.restart();
    }

    Timer {
        id: focusPrimeTimer
        interval: 75
        onTriggered: if (root.isOpen) root._focusPrimed = true
    }

    // Spans the whole screen, not just the card's own right-hand column, for
    // the same reason Panel.qml does: a click landing anywhere outside the
    // card has to close this surface, and a window only as wide as the card
    // never receives that click at all. It goes straight to whatever
    // application is underneath. DismissTwins below only ever covered the
    // OTHER outputs; this is the missing same-output half.
    anchors { top: true; left: true; right: true; bottom: true }

    MouseArea {
        id: backdrop
        anchors.fill: parent
        enabled: root.isOpen
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => keyCatcher.handle(event)
        onClicked: root.close()

        // Enter/exit (spec "Motion"): the whole card fades and slides in from
        // the right edge, one animated scalar so a reopen mid-exit reverses
        // in place.
        Card {
            id: frame
            x: parent.width - root.cardWidth
            y: root._barHeight
            width: root.cardWidth + root._overhang
            height: parent.height - root._barHeight + root._overhang
            // D3 keeps exactly one border, the left one, drawn below so the
            // other three never paint.
            border.width: 0
            opacity: root.isOpen ? 1 : 0
            transform: Translate { x: (1 - frame.opacity) * Theme.motion.slide }

            Behavior on opacity {
                NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
            }

            // Negative margins escape the card's own content inset, the same
            // technique Panel.qml's click swallower uses, so this sits on the
            // frame's actual edge rather than inside its padding.
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: -frame.padding
                anchors.topMargin: -frame.padding
                anchors.bottomMargin: -frame.padding
                width: Theme.borderWidth
                color: Theme.color.border
            }

            // Swallows clicks anywhere inside the frame (its own padding
            // included) before they reach the backdrop above: ordinary
            // nested-MouseArea priority, no manual event plumbing.
            MouseArea {
                anchors.fill: parent
                anchors.margins: -frame.padding
                onClicked: {}
            }

            Item {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: root._overhang
                height: Math.max(title.implicitHeight, clearAllButton.height, dndSwitch.height)

                Text {
                    id: title
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                    color: Theme.color.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.subtitle
                    font.weight: Theme.weight.semibold
                }

                SectionLabel {
                    anchors.right: dndSwitch.left
                    anchors.rightMargin: Theme.space.iconGap
                    anchors.verticalCenter: parent.verticalCenter
                    text: "DND"
                }

                Switch {
                    id: dndSwitch
                    anchors.right: clearAllButton.left
                    anchors.rightMargin: Theme.space.sectionGap
                    anchors.verticalCenter: parent.verticalCenter
                    checked: NotificationService.dnd
                    cursor: root.cursorActive && root.cursorSection === 1
                    onToggled: on => NotificationService.setDnd(on)
                }

                Button {
                    id: clearAllButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    variant: "ghost"
                    text: "Clear all"
                    cursor: root.cursorActive && root.cursorSection === 2
                    onClicked: root.clearAll()
                }
            }

            Flickable {
                id: rowsFlickable
                anchors.top: header.bottom
                anchors.topMargin: Theme.space.sectionGap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: root._overhang
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root._overhang
                clip: true
                contentWidth: width
                contentHeight: column.implicitHeight

                // Never focused: the backdrop owns the keyboard, exactly as
                // Panel.qml wires its own.
                KeyCatcher {
                    id: keyCatcher
                    focus: false
                    width: rowsFlickable.width
                    height: column.implicitHeight
                    blocked: !root.isOpen

                    onMoveRequested: (dx, dy) => root.moveCursor(dx, dy)
                    onActivateRequested: root.activateCursor()
                    onDeleteRequested: root.deleteCursor()
                    onCloseRequested: root.close()
                    onTabRequested: direction => root.moveSection(direction)
                    onTextKey: text => {
                        if (text === "d")
                            root.toggleDnd();
                    }

                    Column {
                        id: column
                        width: parent.width
                        spacing: Theme.space.sectionGap

                        SectionLabel {
                            visible: root._rows.length === 0
                            text: "NO NOTIFICATIONS"
                        }

                        SectionLabel {
                            visible: root._pendingRows.length > 0
                            text: "PENDING"
                            count: NotificationService.pending.length
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.space.rowGap

                            Repeater {
                                model: root._pendingRows

                                delegate: NotificationRow {
                                    id: pendingRow
                                    required property var modelData
                                    required property int index

                                    width: parent.width
                                    entry: pendingRow.modelData
                                    now: root._now
                                    unread: true
                                    cursor: root.cursorActive && root.cursorSection === 0
                                        && root.cursorIndex === pendingRow.index

                                    onDismissRequested: NotificationService.dismissGroup(pendingRow.modelData.memberIds)
                                    onActivateRequested: root.activateRow(pendingRow.modelData)
                                    onActionRequested: key => NotificationService.invokeAction(pendingRow.modelData.id, key)
                                }
                            }
                        }

                        SectionLabel {
                            visible: root._seenRows.length > 0
                            text: "SEEN"
                            count: NotificationService.past.length
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.space.rowGap

                            Repeater {
                                model: root._seenRows

                                delegate: NotificationRow {
                                    id: seenRow
                                    required property var modelData
                                    required property int index

                                    width: parent.width
                                    entry: seenRow.modelData
                                    now: root._now
                                    unread: false
                                    cursor: root.cursorActive && root.cursorSection === 0
                                        && root.cursorIndex === root._pendingRows.length + seenRow.index

                                    onDismissRequested: NotificationService.dismissGroup(seenRow.modelData.memberIds)
                                    onActivateRequested: root.activateRow(seenRow.modelData)
                                    onActionRequested: key => NotificationService.invokeAction(seenRow.modelData.id, key)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Multi-monitor dismiss (M16 Task 7): a click on another screen closes
    // the centre exactly like the bell toggle does.
    DismissTwins {
        active: root.isOpen
        ownScreen: root.screen
        onDismissed: root.close()
    }

    // One history row: the shared NotificationCard, plus the two marks this
    // surface owns rather than the card. Both are drawn here on purpose.
    // Toasts.qml shows the same card with neither, and the card's own chrome
    // is Task 1's to decide.
    //
    // Reports out by signal rather than calling root's own verbs: an inline
    // component is its own type, so ids declared outside it are not in scope
    // here.
    component NotificationRow: Item {
        id: row

        required property var entry
        property double now: 0
        property bool unread: false
        property bool cursor: false

        signal dismissRequested()
        signal activateRequested()
        signal actionRequested(string key)

        // The dot's own width plus a gutter. Reserved on every row, painted
        // on the unread ones, so the two sections stay left-aligned.
        readonly property real _markWidth: Theme.space.md + Theme.space.iconGap

        implicitHeight: card.implicitHeight

        Rectangle {
            visible: row.unread
            width: Theme.space.md
            height: width
            radius: width / 2
            color: Theme.color.primary
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        // The ring, drawn as the halo alone: the card owns its own border, so
        // this surface cannot swap it.
        Rectangle {
            anchors.fill: card
            anchors.margins: -Theme.ringWidth
            visible: row.cursor
            radius: Theme.radiusMd + Theme.ringWidth
            color: Theme.color.ring
            opacity: Theme.ringAlpha
        }

        NotificationCard {
            id: card
            x: row._markWidth
            width: row.width - row._markWidth
            radius: Theme.radiusMd
            entry: row.entry
            now: row.now

            onDismiss: row.dismissRequested()
            onBodyClicked: row.activateRequested()
            onActionInvoked: key => row.actionRequested(key)
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components
import qs.Notifications
import "../../Notifications/model.js" as Model
import "../../Notifications/geometry.js" as Geometry
import "../../Components/cursor.js" as Cursor

// The notification history centre (DESIGN.md §3, spec "Notification
// centre", M44 D3): shadcn's sheet, right-anchored under the bar,
// `popupWidthWide`, drawn as a floating `Card` that is as tall as the
// history it holds and no taller than the output leaves room for (M48 D3,
// geometry.js). Before M48 it was full height and flush against three
// screen edges, which put a long list off the bottom of the screen with
// nothing to scroll.
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
    onIsOpenChanged: {
        NotificationService.centerOpen = root.isOpen;
        if (root.isOpen)
            root._resetRowSlots();
    }

    // Bar.qml publishes its own occupied edge as Theme.edgeInset (the same
    // lookup Panel.qml uses): its thickness on the edge it sits on, 0 on the
    // other three.
    readonly property var _edgeInset: Theme.edgeInset

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

    // --- Row presence (DESIGN.md sec.1 Motion, M51 Task 5) -----------------
    //
    // Mirrors Toasts.qml's own pool of stable slots (its header comment has
    // the full reasoning): a Repeater bound straight to `_pendingRows`/
    // `_seenRows` resets every delegate on any change at all, which is why
    // the Repeaters below bind to a slot COUNT instead and each delegate
    // reads its own slot back out of these arrays by pool index. Visual
    // order comes from `entry.arrivedAt`, the same field `Model.groupEntries`
    // already orders a section by, so a departing row (frozen on its last
    // entry) keeps the position it had rather than jumping to either end
    // while it collapses.
    property var _pendingSlots: []
    property var _seenSlots: []

    // A few pre-made empty slots kept past the current high-water mark: a
    // genuinely new row landing on a slot that already existed a frame
    // earlier gets the ordinary false->true `alive` change its own enter
    // Behavior fires on, rather than a slot's first-ever value, which a
    // Behavior never animates (NotificationRow's `_presence` below).
    readonly property int _slotHeadroom: 3

    function _withHeadroom(slots) {
        var next = slots.slice();
        var free = 0;
        for (var i = next.length - 1; i >= 0 && next[i] === null; i--)
            free++;
        while (free < root._slotHeadroom) {
            next.push(null);
            free++;
        }
        return next;
    }

    // Fresh 1:1 mapping, nothing departing: the centre's own Presence
    // entrance already covers the card materializing, so the rows already
    // on it must not also fade in on top of it. `animated` below is the
    // actual guard (it stays false until that entrance settles); this reset
    // just gives the pool a clean slate to settle into.
    function _resetRowSlots() {
        root._pendingSlots = root._withHeadroom(root._pendingRows.map(function (g) {
            return { key: Model.groupKey(g), entry: g, departing: false };
        }));
        root._seenSlots = root._withHeadroom(root._seenRows.map(function (g) {
            return { key: Model.groupKey(g), entry: g, departing: false };
        }));
    }

    // Reconciles a section's slots against its current rows: a still-live
    // key refreshes in place, a vanished one starts departing (frozen on its
    // last entry so its size holds while it collapses), and a genuinely new
    // key claims the first empty slot or grows the pool.
    function _syncSlots(slots, rows) {
        var liveByKey = {};
        rows.forEach(function (g) { liveByKey[Model.groupKey(g)] = g; });
        var next = slots.slice();
        var occupied = {};
        for (var i = 0; i < next.length; i++) {
            var s = next[i];
            if (!s)
                continue;
            var g = liveByKey[s.key];
            if (g)
                next[i] = { key: s.key, entry: g, departing: false };
            else if (!s.departing)
                next[i] = { key: s.key, entry: s.entry, departing: true };
            occupied[s.key] = true;
        }
        rows.forEach(function (g) {
            var key = Model.groupKey(g);
            if (occupied[key])
                return;
            for (var j = 0; j < next.length; j++) {
                if (!next[j]) {
                    next[j] = { key: key, entry: g, departing: false };
                    occupied[key] = true;
                    return;
                }
            }
            next.push({ key: key, entry: g, departing: false });
        });
        return root._withHeadroom(next);
    }

    on_PendingRowsChanged: {
        if (root.isOpen)
            root._pendingSlots = root._syncSlots(root._pendingSlots, root._pendingRows);
    }
    on_SeenRowsChanged: {
        if (root.isOpen)
            root._seenSlots = root._syncSlots(root._seenSlots, root._seenRows);
    }

    function _clearPendingSlot(index) {
        var slots = root._pendingSlots.slice();
        slots[index] = null;
        root._pendingSlots = slots;
    }
    function _clearSeenSlot(index) {
        var slots = root._seenSlots.slice();
        slots[index] = null;
        root._seenSlots = slots;
    }

    // Per-slot target y, keyed by pool index, and whether that slot draws
    // the rule above it, both read off the arrival order rather than off
    // pool index: `ruled` is still "not first in the section", it just
    // reads that position back out by key instead of straight off the
    // live array.
    function _rowLayout(slots, repeater, descending) {
        var order = [];
        for (var i = 0; i < slots.length; i++) {
            if (slots[i])
                order.push(i);
        }
        order.sort(function (a, b) {
            var da = slots[a].entry.arrivedAt, db = slots[b].entry.arrivedAt;
            return descending ? db - da : da - db;
        });
        var y = {}, ruled = {}, cursor = 0;
        order.forEach(function (index, pos) {
            y[index] = cursor;
            ruled[index] = pos > 0;
            var item = repeater.itemAt(index);
            cursor += (item ? item.height : 0) + Theme.space.rowGap;
        });
        return { y: y, ruled: ruled, height: order.length > 0 ? cursor - Theme.space.rowGap : 0 };
    }

    readonly property var _pendingLayout: root._rowLayout(root._pendingSlots, pendingRepeater, false)
    // Newest first, matching `_pastNewestFirst`.
    readonly property var _seenLayout: root._rowLayout(root._seenSlots, seenRepeater, true)

    // Which single row (either section) the keyboard cursor sits on, read
    // back by key rather than by `cursorIndex` directly: a row's pool index
    // has nothing to do with its position in `_rows`.
    readonly property var _cursorEntry: (root.cursorActive && root.cursorSection === 0
        && root.cursorIndex >= 0 && root.cursorIndex < root._rows.length)
        ? root._rows[root.cursorIndex] : null
    readonly property string _cursorKey: root._cursorEntry ? Model.groupKey(root._cursorEntry) : ""

    // A freed or not-yet-claimed slot's row draws this rather than null,
    // the same stand-in Toasts.qml's empty pool slots use.
    readonly property var _emptyEntry: ({
        id: "", appName: "", appIcon: "", desktopEntry: "", summary: "",
        body: "", urgency: 1, actions: [], image: "", local: false,
        arrivedAt: 0, seenAt: null, expiresAt: null, memberIds: []
    })

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

    readonly property real _screenPadding: Theme.space.screenPadding

    // Header, the rule under it, then the rows (DESIGN.md §3 "Panel", the
    // same seam every panel header draws): one `panelPadding` either side of
    // the rule.
    readonly property real _headerGap: Theme.space.panelPadding * 2 + Theme.borderWidth

    // The card's own height, before the cap: the header, its seam, both row
    // sections, and the Card's padding either side.
    readonly property real _contentHeight: header.height + root._headerGap
        + column.implicitHeight + frame.padding * 2

    // Measured off the output rather than off this window: the window is
    // unmapped while the centre is closed, and a card sized off a window
    // with no size yet would pop to its real height a frame after opening.
    // Panel.qml's own frame maths reads `_screen` for the same reason.
    readonly property var _frame: Geometry.centerFrame({
        screenWidth: root._screen ? root._screen.width : 0,
        screenHeight: root._screen ? root._screen.height : 0,
        insets: root._edgeInset,
        padding: root._screenPadding,
        cardWidth: root.cardWidth,
        contentHeight: root._contentHeight
    })

    // Read back over IPC (`notifications status`): the cap is the whole
    // point of D3 and a screenshot cannot say whether a card that looks
    // short is short because the history is short or because something
    // clipped it.
    readonly property real cardHeight: root._frame.height
    readonly property real cardMaxHeight: root._frame.available
    readonly property bool cardCapped: root._frame.capped

    screen: root._screen
    // Held visible through the exit fade (DESIGN.md §1 Motion): close()
    // drops isOpen, presence's own Behavior runs its progress to 0, and
    // only then does the window unmap. The window itself is transparent so
    // the fade covers the whole card.
    visible: presence.shown
    color: "transparent"

    // The card's own enter/exit recipe (Presence.qml, DESIGN.md §1 Motion,
    // M51 D3): always the right edge, since the card's own x formula
    // (geometry.js's centerFrame) hangs it off the right regardless of
    // which edge the bar occupies.
    Presence {
        id: presence
        open: root.isOpen
        edge: "right"
    }

    // The card's actual height (DESIGN.md §1 Motion, M51 D5): `_frame.height`
    // above is the history's own target, tracked live only while the centre
    // sits open at rest. close() (which seens every pending row, moving it
    // into a different section) simply stops re-syncing this, so the next
    // open snaps straight to that history's real height rather than morphing
    // from the frame the centre closed on. Declared after `presence` so its
    // own settled flip, sharing the isOpenChanged signal this ternary
    // depends on, has already landed by the time this re-evaluates.
    property real _morphHeight: root.isOpen ? root._frame.height : _morphHeight

    Behavior on _morphHeight {
        enabled: presence.settled && root.isOpen
        NumberAnimation { duration: Theme.motion.emphasized; easing.type: Theme.motion.easingInOut }
    }

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

        // Enter/exit lives in Presence (DESIGN.md §1 Motion, M51 D3): fade,
        // zoom and a slide in from the right edge.
        Card {
            id: frame
            x: root._frame.x
            y: root._frame.y
            width: root.cardWidth
            height: root._morphHeight
            // Every edge is inside the output now, so the card keeps the
            // border a Card draws on all four sides rather than the single
            // left one it carried while it was flush against three of them.
            opacity: presence.opacity
            scale: presence.scale
            transformOrigin: presence.transformOrigin

            transform: Translate {
                x: presence.slideX
                y: presence.slideY
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
                height: Theme.space.controlHeight

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

            // The header's seam (DESIGN.md §1's ladder rung 4), full-bleed
            // to the card's border, which the negative margins buy back out
            // of the Card's own padding.
            Separator {
                id: headerRule
                anchors.top: header.bottom
                anchors.topMargin: Theme.space.panelPadding
                anchors.left: parent.left
                anchors.leftMargin: -frame.padding
                anchors.right: parent.right
                anchors.rightMargin: -frame.padding
            }

            // Scrolls only once the card has hit the cap (root._frame.capped):
            // under it the Flickable is exactly as tall as its own column and
            // has nowhere to go.
            Flickable {
                id: rowsFlickable
                anchors.top: headerRule.bottom
                anchors.topMargin: Theme.space.panelPadding
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                contentWidth: width
                contentHeight: column.implicitHeight

                WheelScroll { flickable: rowsFlickable }

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

                    // `sectionGap` between the two sections, `rowGap` inside
                    // one (DESIGN.md §1's ladder, rung 2 carrying rung 3): a
                    // label and its rows have to sit closer to each other
                    // than the label sits to whatever came before it, or the
                    // name floats between two groups instead of heading one.
                    // Each section is one item so its label cannot outlive
                    // its rows.
                    Column {
                        id: column
                        width: parent.width
                        spacing: Theme.space.sectionGap

                        SectionLabel {
                            // Held back while a row is still collapsing out of
                            // either section: it would otherwise sit beside a
                            // fading last row instead of after it.
                            visible: root._rows.length === 0
                                && !root._pendingSlots.some(s => s && s.departing)
                                && !root._seenSlots.some(s => s && s.departing)
                            text: "NO NOTIFICATIONS"
                        }

                        Column {
                            width: parent.width
                            visible: root._pendingRows.length > 0
                                || root._pendingSlots.some(s => s && s.departing)
                            spacing: Theme.space.rowGap

                            SectionLabel {
                                text: "PENDING"
                                count: NotificationService.pending.length
                            }

                            Item {
                                width: parent.width
                                height: root._pendingLayout.height

                                Repeater {
                                    id: pendingRepeater
                                    model: root._pendingSlots.length

                                    delegate: NotificationRow {
                                        id: pendingRow
                                        required property int index
                                        readonly property var _slot: root._pendingSlots[pendingRow.index]
                                        // Gates every Behavior below: the
                                        // centre's own enter (Presence.qml)
                                        // covers the initial population, so a
                                        // row must not also animate until
                                        // that settles, and stops animating
                                        // again once the centre starts
                                        // closing.
                                        readonly property bool _animated: presence.settled && root.isOpen

                                        // Headroom slots (Toasts.qml:420 guards the same
                                        // shape) carry no entry and sit at y 0 under row 0;
                                        // without this an opacity-0 card there still
                                        // hit-tests and swallows row 0's clicks.
                                        visible: pendingRow._slot !== null
                                        width: parent.width
                                        y: root._pendingLayout.y[pendingRow.index] || 0
                                        Behavior on y {
                                            enabled: pendingRow._animated
                                            NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easingInOut }
                                        }

                                        entry: pendingRow._slot ? pendingRow._slot.entry : root._emptyEntry
                                        now: root._now
                                        unread: true
                                        ruled: root._pendingLayout.ruled[pendingRow.index] === true
                                        alive: pendingRow._slot ? !pendingRow._slot.departing : false
                                        animated: pendingRow._animated
                                        cursor: root.cursorActive && root.cursorSection === 0
                                            && pendingRow._slot && pendingRow._slot.key === root._cursorKey

                                        onDismissRequested: NotificationService.dismissGroup(pendingRow._slot.entry.memberIds)
                                        onActivateRequested: root.activateRow(pendingRow._slot.entry)
                                        onActionRequested: key => NotificationService.invokeAction(pendingRow._slot.entry.id, key)
                                        onExited: root._clearPendingSlot(pendingRow.index)
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            visible: root._seenRows.length > 0
                                || root._seenSlots.some(s => s && s.departing)
                            spacing: Theme.space.rowGap

                            SectionLabel {
                                text: "SEEN"
                                count: NotificationService.past.length
                            }

                            Item {
                                width: parent.width
                                height: root._seenLayout.height

                                Repeater {
                                    id: seenRepeater
                                    model: root._seenSlots.length

                                    delegate: NotificationRow {
                                        id: seenRow
                                        required property int index
                                        readonly property var _slot: root._seenSlots[seenRow.index]
                                        readonly property bool _animated: presence.settled && root.isOpen

                                        // Same guard as the pending section above.
                                        visible: seenRow._slot !== null
                                        width: parent.width
                                        y: root._seenLayout.y[seenRow.index] || 0
                                        Behavior on y {
                                            enabled: seenRow._animated
                                            NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easingInOut }
                                        }

                                        entry: seenRow._slot ? seenRow._slot.entry : root._emptyEntry
                                        now: root._now
                                        unread: false
                                        ruled: root._seenLayout.ruled[seenRow.index] === true
                                        alive: seenRow._slot ? !seenRow._slot.departing : false
                                        animated: seenRow._animated
                                        cursor: root.cursorActive && root.cursorSection === 0
                                            && seenRow._slot && seenRow._slot.key === root._cursorKey

                                        onDismissRequested: NotificationService.dismissGroup(seenRow._slot.entry.memberIds)
                                        onActivateRequested: root.activateRow(seenRow._slot.entry)
                                        onActionRequested: key => NotificationService.invokeAction(seenRow._slot.entry.id, key)
                                        onExited: root._clearSeenSlot(seenRow.index)
                                    }
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

    // One history row: the shared NotificationCard, plus the three marks this
    // surface owns rather than the card. All three are drawn here on purpose.
    // Toasts.qml shows the same card with none of them.
    //
    // The card goes flat here and nowhere else: the frame above already draws
    // the fill and the border, so a card per row would tile N of them inside
    // one.
    //
    // `ruled` draws the seam between rows (DESIGN.md §1's ladder, rung 4).
    // These rows are the case that rung is for: each is a stack of its own
    // (sender line, summary, body, sometimes an action row) whose internal
    // gaps are as large as the gap to the next row, so space alone stopped
    // reading as separation and a full centre ran together into one block of
    // text. `rowGap` either side of the rule, which lands it midway between
    // two cards once each has paid its own `panelPadding`.
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
        property bool ruled: false
        // M51 Task 5: false starts this row collapsing (height and opacity
        // together, mirroring Toasts.qml's own presence scalar) instead of
        // vanishing outright, so an arrival or a departure reflows its
        // neighbours rather than popping.
        property bool alive: true
        // Gates the collapse Behavior below. False during the centre's own
        // initial population (its Presence entrance already covers that)
        // and again while it closes; true only for a change that happens
        // with the card already sitting open and settled.
        property bool animated: false

        signal dismissRequested()
        signal activateRequested()
        signal actionRequested(string key)
        // Fired once a departed row's own collapse has fully settled, so the
        // caller can free its pool slot for reuse.
        signal exited()

        // The dot's own width plus a gutter. Reserved on every row, painted
        // on the unread ones, so the two sections stay left-aligned.
        readonly property real _markWidth: Theme.space.md + Theme.space.iconGap

        // What the seam costs the row that draws it: the rule itself and the
        // gap under it. The gap above is the list's own `rowGap` spacing.
        readonly property real _ruleHeight: row.ruled ? Theme.borderWidth + Theme.space.rowGap : 0

        implicitHeight: row._ruleHeight + card.implicitHeight

        // 0 once departed, 1 while alive; height and opacity both ride it so
        // a row collapses and fades as one movement rather than two. Not
        // `readonly`: a Behavior needs to be able to write it, the same way
        // Toasts.qml's own `presence` scalar is left writable despite also
        // being nothing but a binding.
        property real _presence: row.alive ? 1 : 0
        Behavior on _presence {
            enabled: row.animated
            NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easingInOut }
        }
        height: row._presence * row.implicitHeight
        opacity: row._presence
        onOpacityChanged: {
            if (row.opacity === 0 && !row.alive)
                row.exited();
        }

        // Full-bleed across the list, the dot's gutter included: the seam
        // divides the rows, and that gutter is part of a row.
        Separator {
            visible: row.ruled
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
        }

        Rectangle {
            visible: row.unread
            width: Theme.space.md
            height: width
            radius: Theme.pillRadius(width)
            color: Theme.color.primary
            anchors.left: parent.left
            anchors.verticalCenter: card.verticalCenter
        }

        // The ring (DESIGN.md §1), drawn here rather than by the card: a flat
        // card has no resting border for the cursor to swap, so this surface
        // owns both halves. Both are stroked, not filled: Cell.qml can fill
        // its halo because its own opaque body masks the inside of it, and a
        // flat card has nothing to mask with.
        Rectangle {
            anchors.fill: card
            anchors.margins: -Theme.ringWidth
            visible: row.cursor
            radius: Theme.radiusMd + Theme.ringWidth
            color: "transparent"
            border.width: Theme.ringWidth
            border.color: Theme.color.ring
            opacity: Theme.ringAlpha
        }

        Rectangle {
            anchors.fill: card
            visible: row.cursor
            radius: Theme.radiusMd
            color: "transparent"
            border.width: Theme.borderWidth
            border.color: Theme.color.ring
        }

        NotificationCard {
            id: card
            x: row._markWidth
            y: row._ruleHeight
            width: row.width - row._markWidth
            radius: Theme.radiusMd
            flat: true
            entry: row.entry
            now: row.now

            onDismiss: row.dismissRequested()
            onBodyClicked: row.activateRequested()
            onActionInvoked: key => row.actionRequested(key)
        }
    }
}

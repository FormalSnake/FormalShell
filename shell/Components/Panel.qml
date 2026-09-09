import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import "cursor.js" as Cursor
import "geometry.js" as Geometry
import "tooltip.js" as Placement
import "../Bar/layout.js" as BarLayout

// The shared per-widget popout (DESIGN.md §3 "Panel", spec "Panels"): a
// bordered card anchored under the bar cell that opened it, opening with a
// header row (icon, title, ghost icon buttons) and holding whatever sections
// the instantiating panel supplies through its default content slot. Same
// top-layer / OnDemand-keyboard structure as Center.qml/Osd.qml, but, unlike
// either, needs "closes on click-outside" too. Quickshell's PopupWindow gives
// that for free via grabFocus, but its xdg_popup grab needs a real pointer/key
// serial, which panel.open(name) (PanelIpc, headless verification) never has.
// So this stays a plain PanelWindow like every other surface: a transparent,
// exclusiveZone:-1 layer spanning the whole screen, with a backdrop MouseArea
// that closes on any click landing outside the visible frame (the frame's own
// nested MouseArea eats its clicks first, per Qt Quick's normal nested-
// MouseArea priority, so nothing inside it ever falls through).
PanelWindow {
    id: root

    property bool isOpen: false
    // Off for every panel but MediaPanel (M35): keeps this window mapped
    // even while closed, for a caller that needs the surface alive without
    // it being open. MediaPanel's own Video decode has to keep rendering for
    // grabToImage while the bar's mini cover wants frames, and a
    // closed-but-mapped PanelWindow is otherwise unmapped the instant the
    // exit fade finishes (see `visible` below). Default false so no panel
    // besides MediaPanel changes behavior.
    property bool keepMapped: false
    // Shared cursor-visibility gate (upstream's CursorSurface contract):
    // every row gates its cursor paint on this ONE flag rather than reading
    // `containsMouse`/`containsPointer` directly. A mouse entering a row or
    // the first navigation key both flip it true; a fresh open starts it
    // false, so the cursor stays invisible until the user has actually
    // reached for it instead of a stale or default position painting on
    // open.
    property bool cursorActive: false
    property string panelTitle: ""
    // Off for a popout that is a strip rather than a sheet: the tray's
    // overflow bar (Surfaces/Bar/TrayOverflow.qml) is a second bar, and a
    // title row over a line of tray icons would be chrome introducing them.
    // The header row, its seam and both their gaps come out of the frame's
    // own height with it, so the card closes on the content.
    property bool showHeader: true
    // The panel this one opens on top of, for the case where two popouts are
    // genuinely one gesture: a cell that lives in another popout rather than
    // on the bar strip, opening its own. That is a tray item's menu from the
    // tray's second bar (Surfaces/Bar/TrayOverflow.qml), and every widget in
    // the chevron's (Surfaces/Bar/BarOverflow.qml). The registry's "exactly
    // one popout" rule holds everywhere else, and holds here too from the
    // outside: opening anything else still closes both, and the owner closing
    // takes its child with it. What it must not do is treat the surface the
    // click came from as the thing being replaced, which read as the bar
    // shutting the moment you right-clicked an icon in it (owner,
    // 2026-08-28) and as the whole group vanishing the moment you clicked
    // one of its cells (owner, 2026-09-01).
    //
    // Resolved by openFrom() off the anchor cell's own window, so a widget
    // needs to know nothing about where it was instantiated; set directly
    // only on the one path that has no cell to read (TrayMenu's keyboard
    // activation).
    property var owner: null
    // A Lucide name (shell/Theme/icons.js) drawn before the title. Empty
    // leaves the header text-only.
    property string panelIcon: ""
    // The header's own right-side slot, ahead of the close button every
    // panel gets for free. Meant for `IconButton`s.
    property alias titleActions: actionsRow.data
    property int panelWidth: Theme.space.popupWidthDefault
    // The frame's own fill and corner. A panel is a `card` at `radiusXl`
    // (DESIGN.md §3); the tray menu is the one popout that is a menu rather
    // than a panel and takes the `popover` fill at `radiusMd` instead.
    property color frameColor: Theme.surface(Theme.color.card)
    property int frameRadius: Theme.radiusXl
    // Screen-relative centre of the bar cell that opened this panel, mapped
    // within that cell's OWN window (openFrom below). Wayland gives clients
    // no cross-window global coordinates, so mapping the cell into this
    // window's coordinate space instead would be meaningless. -1 means "no
    // cell, opened via IPC", which falls back to the end of the bar, the
    // right region, where every widget cell lives. Which of the two the
    // frame follows is the bar's own axis: x along a top or bottom bar, y
    // along a left or right one.
    property real anchorX: -1
    property real anchorY: -1
    // The output this popout belongs on, taken from the window of the cell
    // that opened it (openFrom below): the monitor you clicked is the monitor
    // the popout has to appear on, whatever the compositor calls focused at
    // that moment, since a bar cell can be clicked without keyboard focus
    // ever leaving another output. Null means nobody named one (an IPC open),
    // and the focused output decides.
    property var anchorScreen: null
    // Focus-prime phase, read only by the keyboardFocus binding below (which
    // carries the full rationale): false for the brief Exclusive prime that
    // actually acquires keyboard focus, true once the surface can settle on
    // OnDemand without losing it.
    property bool _focusPrimed: false
    default property alias content: contentColumn.data

    // --- Keyboard cursor -------------------------------------------------
    //
    // The bookkeeping every keyboard-driven panel shares (spec "Keyboard
    // model"): `cursorCount` is set by the consuming panel to its row count,
    // `cursorIndex` is the row the arrows sit on, and `cursorSection` is
    // which block of the panel Tab has reached (0 is the row list; a panel
    // with a footer control sets `sectionCount: 2`). The maths is in
    // cursor.js.
    property int cursorIndex: 0
    property int cursorCount: 0
    property int cursorSection: 0
    property int sectionCount: 1
    // Set by the panel while one of its `Input`s holds focus: the keys are
    // that field's then, not the cursor's.
    property bool inlineEditorFocused: false

    // Left/Right steps the value on the cursor row rather than walking the
    // list, for a panel whose rows carry an adjustable track (Audio).
    property bool cursorStepsHorizontally: false

    // Above 1, `cursorIndex` addresses a grid of this many columns rather
    // than a list (Calendar's month): Up/Down step a whole week and
    // Left/Right stop at the ends of their own week.
    property int cursorColumns: 1

    signal cursorActivated(int index)
    // `x` on a row that has a destructive action (Bluetooth's forget).
    signal cursorDeleted(int index)
    // A step on the cursor row, `direction` -1 or 1.
    signal cursorStepped(int index, int direction)
    // Any printable key the catcher does not bind itself, for a panel with
    // a single-letter action of its own (Audio's `m`).
    signal cursorTextKey(string text)

    // Forwarded from backdrop's own Keys.onPressed: the raw-event hook for a
    // panel whose keyboard model predates the cursor above (PowerPanel's
    // profile picker, BluetoothPanel's row list). It runs BEFORE the
    // KeyCatcher: a consumer that accepts the event keeps it, and only what
    // nobody claimed reaches the catcher's dispatch. The reverse order would
    // have the catcher swallow Up/Down/Enter out from under every panel that
    // still reads them here.
    signal keyPressed(var event)

    function moveCursor(dx, dy) {
        if (Cursor.isStep(dx, dy, root.cursorStepsHorizontally, root.cursorActive)) {
            root.cursorStepped(root.cursorIndex, dx > 0 ? 1 : -1);
            return;
        }
        var next = Cursor.move(root.cursorIndex, root.cursorCount, root.cursorActive, dx, dy, root.cursorColumns);
        // The halo travels for a key step and only for one (M53 D4): the
        // press that reveals the cursor has nowhere to come from, and the
        // pointer names a row outright rather than stepping to it.
        root._cursorTravels = root.cursorActive && next.index !== root.cursorIndex;
        root.cursorIndex = next.index;
        root.cursorActive = next.active;
        // Deferred so the row's own `cursor` binding, and any reflow the
        // move caused, have both landed before the row is measured.
        Qt.callLater(root._followCursor);
    }

    // --- Scroll-follow ---------------------------------------------------
    //
    // Arrowing past the visible rows of a capped panel brings the cursor row
    // in rather than leaving it under the card's edge (M53 D2, a
    // correctness bug before a motion one: nothing wrote contentY at all).
    //
    // The row is found by walking the content column for the item painting
    // the cursor, which every panel row already declares (`cursor:` on its
    // own Cell), so no panel has to state a second time where its rows are
    // and a row nested inside a section reports its real y. Depth first, so
    // a row whose own control also takes the cursor (Audio's tracks) reports
    // the row rather than the control.
    //
    // Driven from moveCursor and nowhere else: the pointer moves the cursor
    // too (every panel's `_pointAt`), and a wheel notch that slides a new
    // row under a parked pointer must not then scroll the list again.
    property real _followY: 0
    // Set for the one write that resyncs `_followY` with a contentY the
    // wheel or a drag moved, which has to land instantly.
    property bool _followSync: false

    Behavior on _followY {
        enabled: !root._followSync
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    on_FollowYChanged: contentFlickable.contentY = root._followY

    function _cursorRow(item) {
        if (!item || !item.visible)
            return null;
        if (item.cursor === true)
            return item;
        var kids = item.children;
        for (var i = 0; i < kids.length; i++) {
            var found = root._cursorRow(kids[i]);
            if (found)
                return found;
        }
        return null;
    }

    function _followCursor() {
        if (!root.isOpen || !root.cursorActive)
            return;
        var row = root._cursorRow(contentColumn);
        if (!row)
            return;
        var next = Cursor.follow(row.mapToItem(contentColumn, 0, 0).y + Theme.ringWidth, row.height,
            contentFlickable.contentY, contentFlickable.height, contentFlickable.contentHeight,
            Theme.ringWidth);
        if (next === contentFlickable.contentY)
            return;
        root._followSync = true;
        root._followY = contentFlickable.contentY;
        root._followSync = false;
        root._followY = next;
    }

    // --- The cursor halo -------------------------------------------------
    //
    // One ring halo for the whole panel rather than one per row (M53 D4), so
    // that an arrow key moves a cursor instead of turning one off and
    // another on. The rows keep their `cursor` flag, which still colours
    // their border and their ink and is still what `_cursorRow` above finds
    // them by; what left them is the halo itself, suppressed inside anything
    // declaring `ownsCursorHalo` (Cell.qml's own note).
    //
    // Positioned by hand rather than bound: the row is found by walking the
    // tree, which is not a dependency QML can re-evaluate, and its place in
    // the content column is a mapToItem, which is not one either. Deferred
    // for the same reason the scroll-follow above is, and off the same
    // moves: whatever changed the cursor has to have reflowed first.
    property bool _cursorTravels: false

    onCursorIndexChanged: Qt.callLater(root._syncCursorHalo)
    onCursorActiveChanged: Qt.callLater(root._syncCursorHalo)
    onCursorSectionChanged: Qt.callLater(root._syncCursorHalo)
    onIsOpenChanged: Qt.callLater(root._syncCursorHalo)

    function _syncCursorHalo() {
        var row = (root.isOpen && root.cursorActive) ? root._cursorRow(contentColumn) : null;
        cursorHalo.row = row;
        if (!row) {
            root._cursorTravels = false;
            return;
        }
        var at = row.mapToItem(contentColumn, 0, 0);
        var radius = row.radius === undefined ? Theme.radiusMd : row.radius;
        cursorHalo.radius = radius + Theme.ringWidth;
        cursorHalo.x = at.x - Theme.ringWidth;
        cursorHalo.y = at.y - Theme.ringWidth;
        cursorHalo.width = row.width + Theme.ringWidth * 2;
        cursorHalo.height = row.height + Theme.ringWidth * 2;
        root._cursorTravels = false;
    }

    function activateCursor() {
        var index = Cursor.activation(root.cursorIndex, root.cursorCount, root.cursorActive, root.cursorSection);
        if (index >= 0)
            root.cursorActivated(index);
    }

    function deleteCursor() {
        var index = Cursor.activation(root.cursorIndex, root.cursorCount, root.cursorActive, root.cursorSection);
        if (index >= 0)
            root.cursorDeleted(index);
    }

    function moveSection(direction) {
        root.cursorSection = Cursor.section(root.cursorSection, root.sectionCount, direction);
        root.cursorActive = true;
    }

    // Hands the keyboard back to the panel after an inline editor gave it
    // up: a field that goes invisible leaves the window with no focus item
    // at all, and the surface would stop answering keys entirely.
    function takeKeyboard() {
        backdrop.forceActiveFocus();
    }

    readonly property var _screen: {
        if (root.anchorScreen) return root.anchorScreen;
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    // One padding rule (DESIGN.md §1, M48 D3): every floating surface sits
    // `barMargin` off the bar's inner edge and `screenPadding` in from the
    // screen edges it runs between. A cell-anchored open is centred on the
    // cell, clamped so neither end can push the frame past that padding; an
    // IPC open has no cell to anchor to and falls back to the end of the
    // bar. Which edge the bar is on (Theme.barPosition) decides which of
    // x and y follows the cell and which hangs off the bar.
    // A panel with an owner hangs off the OWNER, not off the bar: both are
    // pinned to the same edge by the same rule above, so a child would
    // otherwise draw straight on top of the surface it belongs to (owner,
    // 2026-08-28, a tray item's menu over the tray's second bar). One
    // `barMargin` clear of it, on the axis that hangs off the bar, which is
    // the one axis both of them are pinned on: beside it on a vertical bar,
    // under it on a horizontal one.
    //
    // Both of these read the ANIMATED size (`_morphWidth`/`_morphHeight`
    // below), never the content's target: the frame hangs off the bar's
    // inner edge, and on a bottom, left or right bar that edge is the one
    // the card's own size decides. Reading the target instead placed the
    // card where it was about to be and left it detached from the bar for
    // the whole 250ms morph (M53 D2).
    readonly property real _ownerShift: (root.owner && root.owner.isOpen)
        ? (Theme.space.barMargin + (Theme.barVertical ? root.owner._morphWidth : root.owner._morphHeight))
        : 0

    readonly property real _frameX: root._screen
        ? Geometry.frameX(Theme.barPosition, root.anchorX, root._screen.width, root._morphWidth,
            Theme.edgeInset, Theme.space.barMargin, Theme.space.screenPadding) - root._edge.x * root._ownerShift
        : 0
    readonly property real _frameY: root._screen
        ? Geometry.frameY(Theme.barPosition, root.anchorY, root._screen.height, root._morphHeight,
            Theme.edgeInset, Theme.space.barMargin, Theme.space.screenPadding) - root._edge.y * root._ownerShift
        : 0

    // Where the frame emerges from: the bar's edge.
    readonly property var _edge: BarLayout.edgeVector(Theme.barPosition)

    // What the card is allowed to paint on (M53 addendum, the drawer open):
    // everything past the bar's inner line, which is also the card's own
    // resting edge. The emerge below displaces a closed card behind that
    // line by its whole extent, and this is what cuts it there.
    readonly property var _clipBand: root._screen
        ? Geometry.clipBand(Theme.barPosition, root._screen.width, root._screen.height,
            Theme.edgeInset, Theme.space.barMargin, root._ownerShift)
        : ({ x: 0, y: 0, width: 0, height: 0 })

    readonly property real _contentWidth: root.panelWidth - Theme.space.panelPadding * 2

    // The tallest the frame may be: under a top or bottom bar, the screen
    // minus the bar, the `barMargin` the frame hangs off it by, and one
    // `screenPadding` at the far edge; beside a vertical bar, the screen
    // minus both paddings. Content beyond that scrolls (contentFlickable
    // below) rather than the panel running off the display, which the
    // notification centre and a long calendar month both did.
    // On a horizontal bar the shift above eats into the room below, so the
    // cap comes down with it and a long menu scrolls rather than running off
    // the screen. On a vertical bar the shift is sideways and the height is
    // untouched.
    readonly property real _maxFrameHeight: root._screen
        ? Geometry.maxFrameHeight(Theme.barPosition, root._screen.height, Theme.edgeInset,
            Theme.space.barMargin, Theme.space.screenPadding) - (Theme.barVertical ? 0 : root._ownerShift)
        : 400
    // Header, the rule under it, then the content column (DESIGN.md §3
    // "Panel"): one `panelPadding` either side of the seam, so the header
    // sits in the same gutter the card's own padding gives every other edge.
    // Both terms are 0 on a headerless panel, which is the whole of what
    // `showHeader` costs: the content then starts at the card's own padding.
    readonly property real _headerHeight: root.showHeader ? Theme.space.controlHeight : 0
    readonly property real _headerGap: root.showHeader ? Theme.space.panelPadding * 2 + Theme.borderWidth : 0

    readonly property real _maxContentHeight: Geometry.maxContentHeight(root._maxFrameHeight,
        Theme.space.panelPadding, root._headerHeight, root._headerGap)
    readonly property real _frameHeight: Geometry.frameHeight(contentColumn.implicitHeight,
        root._maxContentHeight, Theme.space.panelPadding, root._headerHeight, root._headerGap)

    // --- Handoff ---------------------------------------------------------
    //
    // Opening B while A is open is one card, not two surfaces crossing (M53
    // D5): B's frame is seeded on A's rect and, once the two contents have
    // crossfaded there, travels to its own. Since both are a `card` fill
    // with the same border and radius, and A's card is cut the moment the
    // crossfade ends, what the eye gets is one card whose contents change
    // and which then moves and resizes into place.
    //
    // The two phases are sequential rather than concurrent because two
    // Wayland surfaces cannot commit a frame together: overlapped, the pair
    // drew a doubled edge a frame's travel apart, which at this distance was
    // 160px. Stationary they sit exactly on top of each other, and by the
    // time anything moves there is only one card left.
    //
    // The card itself never crossfades, which is why Presence is bypassed on
    // both halves, and why the outgoing window is cut rather than faded: an
    // exit fade would drag a shrinking ghost border across the card that has
    // already taken its place.

    // Non-null on the incoming half for the whole travel: the rect the frame
    // starts from.
    property var _handoffFrom: null
    // How far along that travel the frame is, 0 at `_handoffFrom` and 1 at
    // this panel's own place. One animation rather than a Behavior on the
    // frame: a Behavior would need the seed, the arming and the retarget to
    // land in that order across a window that is still mapping, and they do
    // not.
    property real _travel: 1
    // Non-null on the outgoing half: the panel taking this card over. The
    // frame itself does not move for it, the two morphs having frozen where
    // they were; what it names is whose content is fading in under this
    // one's, and that this window is a handed-over card rather than a
    // closing one.
    property var _handoffTo: null
    // Non-null on the incoming half over the same window as `_handoffFrom`:
    // the outgoing panel, waiting to be told the travel has begun.
    property var _handoffPending: null
    // Armed for the whole travel on both halves.
    property bool _handoff: false
    // Set the instant a handed-over card's travel ends, cleared by the next
    // open. The window goes on it.
    property bool _handedOver: false
    readonly property bool handingOver: root._handoff && root._handoffTo !== null

    // The frame's rect right now, in the output's own coordinates: what a
    // handoff hands over. This window covers the whole output, so the
    // frame's own x and y already are those coordinates.
    readonly property rect frameRect: Qt.rect(frame.x, frame.y, frame.width, frame.height)

    // The card's contents (the header, its seam and the row list), which
    // crossfade across a handoff while the card itself does not.
    property real _contentAlpha: 1
    // What those three actually draw at. The outgoing half reads the
    // incoming one's alpha rather than running a fade of its own: one clock,
    // which a window that has yet to render its first frame cannot be
    // behind, and the pair are exactly complementary at every step.
    // Presence's own term is what holds the contents back behind the emerge,
    // so the card arrives before its text; it is 1 whenever the surface is at
    // rest or bypassed, which leaves the handoff crossfade below alone.
    readonly property real _contentOpacity: ((root.handingOver && root._handoffTo)
        ? 1 - root._handoffTo._contentAlpha
        : root._contentAlpha) * presence.contentOpacity
    // Set for the one write that seeds the alpha on an open, which has to
    // land instantly rather than glide from whatever the last close left.
    property bool _alphaSync: false

    Behavior on _contentAlpha {
        enabled: !root._alphaSync
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    // What this half of the handoff has left to live. Set on each phase
    // rather than bound, since the two halves and the wait for the incoming
    // window are three different lengths.
    property int _handoffLife: 0

    Timer {
        id: handoffTimer
        interval: root._handoffLife
        onTriggered: root.endHandoff()
    }

    // A generous wait, not a duration: a cold panel's window can take a few
    // hundred milliseconds to map, and a clock that ran out first would cut
    // the outgoing card with nothing yet to replace it.
    function _handoffBackstop() {
        return Theme.motion.emphasized * 8;
    }

    SequentialAnimation {
        id: travelAnimation
        PauseAnimation { duration: Theme.motion.standard }
        NumberAnimation {
            target: root
            property: "_travel"
            from: 0
            to: 1
            duration: Theme.motion.emphasized
            easing.type: Theme.motion.easingInOut
        }
    }

    // The outgoing half. It closes, so keyboard focus, the backdrop and the
    // registry slot all release on this tick exactly as an ordinary close
    // does, and its card stays where it is with `next`'s card seeded on top
    // of it. close() first, since close() is also what ends a handoff.
    function handOver(next) {
        root.close();
        root._handoff = true;
        root._handoffTo = next;
        root._handoffLife = root._handoffBackstop();
        handoffTimer.restart();
    }

    // The incoming half, seeded at the outgoing card's rect.
    function takeOver(rect, outgoing) {
        root._travel = 0;
        root._handoffFrom = rect;
        root._handoff = true;
        root._handoffPending = outgoing;
        root._handoffLife = root._handoffBackstop();
        handoffTimer.restart();
        if (root.backingWindowVisible)
            Qt.callLater(root._beginTravel);
    }

    // Both halves start here, once this window is really up: see the block
    // header for why a cold map is what decides the moment.
    function _beginTravel() {
        if (!root._handoff || !root._handoffPending)
            return;
        var outgoing = root._handoffPending;
        root._handoffPending = null;
        root._contentAlpha = 1;
        root._handoffLife = Theme.motion.standard + Theme.motion.emphasized;
        travelAnimation.restart();
        handoffTimer.restart();
        outgoing.beginTravel();
    }

    // Called on the outgoing half by the incoming one: its content is
    // already following the incoming's, so all this sets is how long this
    // window has left. It is the crossfade, not the travel: past that, the
    // card standing on this rect is the incoming one and this is a duplicate
    // of it that must not still be here when it moves.
    function beginTravel() {
        if (!root._handoff)
            return;
        root._handoffLife = Theme.motion.standard;
        handoffTimer.restart();
    }

    function endHandoff() {
        if (!root._handoff)
            return;
        handoffTimer.stop();
        travelAnimation.stop();
        root._travel = 1;
        root._handedOver = root.handingOver;
        root._handoff = false;
        root._handoffFrom = null;
        root._handoffTo = null;
        root._handoffPending = null;
        root._handoffLife = 0;
    }

    function _seedContent(alpha) {
        root._alphaSync = true;
        root._contentAlpha = alpha;
        root._alphaSync = false;
    }

    // `anchor` is the opening cell's centre ({x, y}) in its own window, or
    // undefined for an open with no cell.
    function open(anchor, screen) {
        // First, because both of them decide where this frame is about to
        // land and the handoff below is a question about that place.
        root.anchorX = anchor ? anchor.x : -1;
        root.anchorY = anchor ? anchor.y : -1;
        root.anchorScreen = screen !== undefined ? screen : null;

        var previous = PanelRegistry.current;
        var replacing = previous && previous !== root && previous !== root.owner;
        // Asked before anything moves: the outgoing frame is only where it
        // was until this panel takes the slot.
        var from = replacing ? PanelRegistry.beginHandoff(previous, root) : null;
        if (replacing && !from)
            previous.close();
        PanelRegistry.current = root;
        root._handedOver = false;
        root._seedContent(from ? 0 : 1);
        root.isOpen = true;
        // Both halves in one pass, and the outgoing one last: it aims at
        // this panel's resolved place, which is only worth reading once
        // isOpen has unfrozen the two morphs it is built out of.
        if (from) {
            root.takeOver(from, previous);
            previous.handOver(root);
        }
        root._focusPrimed = false;
        root._beginFocusPrime();
        Qt.callLater(function () { backdrop.forceActiveFocus(); });
    }

    function close() {
        root.endHandoff();
        // A card still on its way to this one has nowhere left to go.
        var handoff = PanelRegistry.handoff;
        if (handoff && handoff.to === root && handoff.from && handoff.from !== root)
            handoff.from.endHandoff();
        root.isOpen = false;
        root.cursorActive = false;
        // The slot goes back to whoever this opened on top of, so the next
        // open closes that one rather than leaving it behind.
        if (PanelRegistry.current === root)
            PanelRegistry.current = (root.owner && root.owner.isOpen) ? root.owner : null;
    }

    function toggle(anchor, screen) {
        if (root.isOpen) root.close();
        else root.open(anchor, screen);
    }

    // The entry point every bar cell uses: both answers a popout needs, which
    // output and where along it, come off the cell's own window, since
    // Wayland hands clients no cross-window geometry. Same `QsWindow.window`
    // idiom Tooltip.qml resolves its own anchor through.
    function openFrom(item) {
        var window = item ? item.QsWindow.window : null;
        // A cell inside another popout opens on top of it, never in place of
        // it: `owner` above carries the rest. The bar strip's own window is a
        // PanelWindow with no `isOpen` of its own, so a bar cell resolves to
        // no owner and this stays the ordinary case.
        root.owner = (window && window !== root && window.isOpen !== undefined) ? window : null;
        var anchor;
        if (item && window) {
            var origin = item.mapToItem(null, 0, 0);
            var offset = Placement.windowOrigin(window.anchors,
                Qt.size(window.width, window.height),
                Qt.size(window.screen.width, window.screen.height));
            anchor = Qt.point(origin.x + offset.x + item.width / 2,
                origin.y + offset.y + item.height / 2);
        }
        root.open(anchor, window ? window.screen : null);
    }

    function toggleFrom(item) {
        if (root.isOpen) root.close();
        else root.openFrom(item);
    }

    screen: root._screen
    // Held visible through the exit fade (DESIGN.md §1 "Motion"): close()
    // drops isOpen, presence's own Behavior runs its progress to 0, and
    // only then does the window unmap. Keyboard focus and the backdrop
    // release on isOpen itself, so input never lands on a fading-out panel.
    // `keepMapped` extends this past the fade for MediaPanel's grabToImage
    // need (M35).
    // A handed-over window is cut, never faded: the card that replaced it is
    // already drawn at exactly its rect, so Presence's own exit would only
    // draw a shrinking ghost of this one over it.
    visible: root.keepMapped || (!root._handedOver && presence.shown)
    color: "transparent"
    // keepMapped alone (closed, fully faded, still mapped) is the one state
    // that must take no input at all: an empty Region resolves to an empty
    // QRegion, which QsWindow.mask turns into WindowTransparentForInput, real
    // click-through rather than a disabled MouseArea (Tooltip.qml's own
    // precedent), so a "closed" panel kept mapped for its Video decode never
    // eats a click meant for whatever is really on screen there.
    // A card mid-handoff is drawn but no longer anybody's: it sits over the
    // panel that took its place and must not eat that panel's clicks.
    mask: (root.handingOver || (!presence.shown && root.keepMapped)) ? _clickThroughMask : null

    Region { id: _clickThroughMask }

    // The frame's own enter/exit recipe (Presence.qml, DESIGN.md §1
    // "Motion"): a drawer out of the bar's own edge, since that is what every
    // panel hangs off. The extent is the card's size across that edge, so a
    // closed card sits exactly its own height (or width, beside a vertical
    // bar) behind the line `_clipBand` cuts at.
    Presence {
        id: presence
        // A card being handed over stays at its open pose for the length of
        // the travel: it is not exiting, it is turning into the next panel.
        open: root.isOpen || root.handingOver
        bypass: root._handoff
        edge: Theme.barPosition
        // The travel waits for the surface: a cold panel's window takes long
        // enough to come up that an emerge started on the open would be over
        // before anything of it was on screen.
        mapped: root.backingWindowVisible
        mode: "emerge"
        extent: Theme.barVertical ? root._morphWidth : root._morphHeight
    }

    // The frame's actual height (DESIGN.md §1 Motion, M51 D5): `_frameHeight`
    // above is the content's own target, tracked live only while the panel
    // sits open at rest, so a size change never fights the enter/exit fade.
    // close() simply stops re-syncing this, so whatever open() finds next is
    // the real content height, never a morph from the frame the panel closed
    // on. Declared after `presence` so its own settled flip, which shares
    // the isOpenChanged signal this ternary depends on, has already landed
    // by the time this re-evaluates.
    property real _morphHeight: root.isOpen ? root._frameHeight : _morphHeight

    Behavior on _morphHeight {
        // Off through a handoff: the frame's own size Behaviors below carry
        // the travel then, and two clocks on one size would fight.
        enabled: presence.settled && root.isOpen && !root._handoff
        NumberAnimation { duration: Theme.motion.emphasized; easing.type: Theme.motion.easingInOut }
    }

    // The width's twin, on the same freeze and the same clock. A panel that
    // measures its own width (BarOverflow and TrayOverflow both bind
    // `panelWidth` to the rail they hold) changes it while it is open, and
    // that has to travel the way a new height does.
    property real _morphWidth: root.isOpen ? root.panelWidth : _morphWidth

    Behavior on _morphWidth {
        enabled: presence.settled && root.isOpen && !root._handoff
        NumberAnimation { duration: Theme.motion.emphasized; easing.type: Theme.motion.easingInOut }
    }

    // Where the frame sits: its own place, or, on the incoming half of a
    // handoff, somewhere on the line from the rect it took over to that.
    // `own` is read live rather than snapshotted, so content that settles
    // its height a frame late moves the destination rather than stranding
    // the travel short of it.
    readonly property rect _framePlace: {
        var own = Qt.rect(root._frameX, root._frameY, root._morphWidth, root._morphHeight);
        if (!root._handoffFrom)
            return own;
        var from = root._handoffFrom;
        var t = root._travel;
        return Qt.rect(from.x + (own.x - from.x) * t,
            from.y + (own.y - from.y) * t,
            from.width + (own.width - from.width) * t,
            from.height + (own.height - from.height) * t);
    }

    WlrLayershell.namespace: "formalshell:panel"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    // Keyboard focus follows isOpen, never `visible`: the surface stays
    // mapped through the exit fade above, but input ownership has to release
    // the instant close() fires.
    //
    // OnDemand on its own is not enough to make a keyboard-summoned panel
    // usable: wlroots only hands an OnDemand surface focus once the
    // compositor routes it there, i.e. after a click. `qs ipc call panel open
    // audio` from a compositor keybind therefore produced a panel where
    // Escape did nothing and PowerPanel's arrow keys were dead. So every
    // open() primes with Exclusive, which takes focus unconditionally, both
    // at map time and when an already-mapped fade-out surface is resummoned,
    // then settles back to OnDemand once that focus has landed.
    //
    // ⚠️ Do NOT "simplify" this to the plain Exclusive binding Menu.qml and
    // PolkitDialog.qml can afford. Hyprland routes EVERY pointer event to an
    // exclusive-focus surface regardless of which output the cursor is over,
    // so a permanently-exclusive panel leaves clicks on every other monitor
    // dead, including the DismissTwins catchers below, whose entire job is
    // dismissing this panel from another output. Omarchy hit and documented
    // exactly this (its `shell/Ui/KeyboardPanel.qml` header comment); the
    // prime window is kept short so that grab is never perceptible.
    WlrLayershell.keyboardFocus: root.isOpen
        ? (root._focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
        : WlrKeyboardFocus.None

    // A cold open flips `visible` before the surface exists, so open()'s own
    // call finds no backing window yet and the timer below never starts:
    // this catches the map itself. A reopen mid-fade never changes this flag
    // (the window stayed mapped throughout), which is why open() arms the
    // prime as well. Between them every open path is covered exactly once.
    onBackingWindowVisibleChanged: {
        root._beginFocusPrime();
        if (root.backingWindowVisible)
            Qt.callLater(root._beginTravel);
    }

    function _beginFocusPrime() {
        if (root.isOpen && root.backingWindowVisible)
            focusPrimeTimer.restart();
    }

    Timer {
        id: focusPrimeTimer
        // Room for several Qt/Wayland commit cycles (the compositor grants
        // focus on the commit carrying the Exclusive role, not on the QML
        // property write) while keeping the compositor-wide pointer grab
        // described above far too brief to notice.
        interval: 75
        onTriggered: if (root.isOpen) root._focusPrimed = true
    }

    anchors { top: true; left: true; right: true; bottom: true }

    MouseArea {
        id: backdrop
        anchors.fill: parent
        enabled: root.isOpen
        focus: true
        // Explicit despite matching Item's own default: states outright that
        // row navigation has to win over contentFlickable's scroll, which is
        // a descendant of this MouseArea and never holds focus of its own
        // (open() always forces it here), so key events land here first
        // regardless. This pins that contract rather than leaning on it.
        Keys.priority: Keys.BeforeItem
        Keys.onEscapePressed: root.close()
        Keys.onPressed: event => {
            root.keyPressed(event);
            if (!event.accepted)
                keyCatcher.handle(event);
        }
        onClicked: root.close()

        // The drawer's slit (M53 addendum): everything the card paints is cut
        // at the bar's inner line, so the emerge below comes out from under
        // the bar rather than passing over it. Only the card is inside: the
        // backdrop above still spans the whole output, since a click landing
        // on the bar has to close the panel too.
        Item {
            id: clipper
            x: root._clipBand.x
            y: root._clipBand.y
            width: root._clipBand.width
            height: root._clipBand.height
            clip: true

            // Puts the output's own coordinates back for everything under it,
            // so the frame's x and y (and with them the rect a handoff hands
            // over) stay window coordinates rather than becoming offsets into
            // the band.
            Item {
                x: -clipper.x
                y: -clipper.y
                width: backdrop.width
                height: backdrop.height

                Card {
                    id: frame
                    x: root._framePlace.x
                    y: root._framePlace.y
                    width: root._framePlace.width
                    height: root._framePlace.height
                    color: root.frameColor
                    radius: root.frameRadius

                    // A morph that moves the card as well as resizing it (a centred
                    // frame growing, a measured panel widening, the owner under it
                    // changing height) travels rather than jumps, on the same clock
                    // and curve the size itself rides. Gated like the two morphs
                    // above, so a fresh open lands at its real place instead of
                    // gliding there from wherever the last open left the card:
                    // open() flips isOpen, which drops presence.settled in the same
                    // pass, well before either coordinate re-evaluates.
                    // Off through a handoff, which draws its own trajectory: one
                    // clock over the frame, never two.
                    Behavior on x {
                        enabled: !root._handoff && presence.settled && root.isOpen
                        NumberAnimation { duration: Theme.motion.emphasized; easing.type: Theme.motion.easingInOut }
                    }

                    Behavior on y {
                        enabled: !root._handoff && presence.settled && root.isOpen
                        NumberAnimation { duration: Theme.motion.emphasized; easing.type: Theme.motion.easingInOut }
                    }

                    // Enter/exit lives in Presence (DESIGN.md §1 "Motion", M53
                    // addendum): the drawer. The card is displaced toward the bar
                    // by its own extent while closed and travels out from under
                    // `clipper`'s line, with no fade and no zoom of its own, so
                    // what opens is a card coming out of the bar rather than one
                    // materialising under it. A handed-over card is cut outright
                    // (see the handoff block above), which is what the opacity
                    // term is left for.
                    opacity: root._handedOver ? 0 : presence.opacity

                    transform: Translate {
                        x: presence.emergeX
                        y: presence.emergeY
                    }

                    // Swallows clicks anywhere inside the frame (the card's own
                    // padding included) before they ever reach the backdrop above:
                    // ordinary nested-MouseArea priority, no manual event plumbing.
                    // The negative margins undo the card's content inset, which this
                    // has to cover.
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -frame.padding
                        onClicked: {}
                    }

                    // The pointer leaving the card takes the cursor with it. A row
                    // the pointer enters takes the cursor (every panel's own
                    // `_pointAt`), and with nothing to clear it the last row kept
                    // its ring after the pointer had gone, which reads as a hover
                    // that never ended (owner, 2026-08-26). The next key or the next
                    // row entered puts it back. On `frame` itself, padding included,
                    // so crossing the card's own gutter is not a leave.
                    HoverHandler {
                        parent: frame
                        onHoveredChanged: if (!hovered) root.cursorActive = false
                    }

                    // A header row is `controlHeight` tall (DESIGN.md §1 Padding),
                    // stated rather than inferred from whichever control inside it
                    // happens to be tallest.
                    // The header, its seam and the rows carry the handoff crossfade;
                    // the card under them does not (see the handoff block above).
                    Item {
                        id: header
                        visible: root.showHeader
                        opacity: root._contentOpacity
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: root._headerHeight

                        Icon {
                            id: headerIcon
                            visible: root.panelIcon !== ""
                            name: root.panelIcon
                            size: Theme.fontSize.subtitle
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            id: titleText
                            anchors.left: headerIcon.visible ? headerIcon.right : parent.left
                            anchors.leftMargin: headerIcon.visible ? Theme.space.iconGap : 0
                            anchors.right: actionsRow.left
                            anchors.rightMargin: Theme.space.iconGap
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.panelTitle
                            color: Theme.color.foreground
                            font.family: Theme.fontFamilySans
                            font.pixelSize: Theme.fontSize.subtitle
                            font.weight: Theme.weight.semibold
                            elide: Text.ElideRight
                        }

                        Row {
                            id: actionsRow
                            anchors.right: closeButton.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.space.xs
                        }

                        IconButton {
                            id: closeButton
                            name: "x"
                            tooltipText: "Close"
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: root.close()
                        }
                    }

                    // The header's seam (DESIGN.md §1's ladder rung 4, §3 "Panel"):
                    // every panel draws it, so the card reads as a titled sheet
                    // rather than as a title floating over a list. Full-bleed, which
                    // the negative margins buy back out of the Card's own padding:
                    // a rule stopping short of the border would read as a division
                    // of the rows rather than of the card.
                    Separator {
                        id: headerRule
                        visible: root.showHeader
                        opacity: root._contentOpacity
                        anchors.top: header.bottom
                        anchors.topMargin: Theme.space.panelPadding
                        anchors.left: parent.left
                        anchors.leftMargin: -frame.padding
                        anchors.right: parent.right
                        anchors.rightMargin: -frame.padding
                    }

                    // The ring reservation (DESIGN.md §1 "Ring", M48 D2): a clipping
                    // container grows its clip rect by `ringWidth` on every side and
                    // insets its content by the same, so the halo a cursor row draws
                    // outside its own border has somewhere to land and every row
                    // keeps the x, width and top it had without one. The overhang
                    // eats `ringWidth` of the card's own padding and of the gap under
                    // the header, both of which are several times that.
                    Flickable {
                        id: contentFlickable
                        opacity: root._contentOpacity
                        // Held off the card's own inner top by the header and its
                        // seam rather than anchored under the rule itself, so a
                        // headerless panel (both terms 0) starts where the card's
                        // padding leaves off instead of under an invisible rule.
                        anchors.top: parent.top
                        anchors.topMargin: root._headerHeight + root._headerGap - Theme.ringWidth
                        anchors.left: parent.left
                        anchors.leftMargin: -Theme.ringWidth
                        anchors.right: parent.right
                        anchors.rightMargin: -Theme.ringWidth
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -Theme.ringWidth
                        clip: true
                        contentWidth: width
                        contentHeight: contentColumn.implicitHeight + Theme.ringWidth * 2

                        WheelScroll { flickable: contentFlickable }

                        // Never focused: the backdrop owns the keyboard (see its
                        // Keys.onPressed, which drives this by hand so `keyPressed`
                        // consumers get first refusal).
                        KeyCatcher {
                            id: keyCatcher
                            focus: false
                            x: Theme.ringWidth
                            y: Theme.ringWidth
                            width: contentFlickable.width - Theme.ringWidth * 2
                            height: contentColumn.implicitHeight
                            blocked: Cursor.catcherBlocked(root.isOpen, root.inlineEditorFocused)

                            // What Cell.qml reads off its ancestors: every row under
                            // here leaves its halo to `cursorHalo` below.
                            property bool ownsCursorHalo: true

                            onMoveRequested: (dx, dy) => root.moveCursor(dx, dy)
                            onActivateRequested: root.activateCursor()
                            onDeleteRequested: root.deleteCursor()
                            onCloseRequested: root.close()
                            onTabRequested: direction => root.moveSection(direction)
                            onTextKey: text => root.cursorTextKey(text)

                            // Under the rows rather than over them, and outside the
                            // Column, which would lay a bare rectangle out as a row
                            // of its own.
                            Rectangle {
                                id: cursorHalo
                                property Item row: null
                                z: -1
                                visible: cursorHalo.row !== null
                                color: Theme.color.ring
                                opacity: Theme.ringAlpha

                                Behavior on x {
                                    enabled: root._cursorTravels
                                    NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
                                }
                                Behavior on y {
                                    enabled: root._cursorTravels
                                    NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
                                }
                                Behavior on width {
                                    enabled: root._cursorTravels
                                    NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
                                }
                                Behavior on height {
                                    enabled: root._cursorTravels
                                    NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
                                }
                            }

                            Column {
                                id: contentColumn
                                width: parent.width
                                spacing: Theme.space.sectionGap

                                // The frame's own `_morphHeight` carries every height
                                // change inside this column, so a control that would
                                // otherwise animate its own (Input's error caption)
                                // lays out at the target and lets the card travel to
                                // it. cursor.js documents the walk.
                                property bool ownsSizeMorph: true

                                // A row appearing, leaving or changing height moves
                                // the cursor row without the cursor itself moving.
                                onImplicitHeightChanged: Qt.callLater(root._syncCursorHalo)
                            }
                        }
                    }
                }
            }
        }
    }

    // Multi-monitor dismiss (M16 Task 7): backdrop above only ever catches
    // clicks on this panel's own output.
    DismissTwins {
        active: root.isOpen
        ownScreen: root.screen
        onDismissed: root.close()
    }
}

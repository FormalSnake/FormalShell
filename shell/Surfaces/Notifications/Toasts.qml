import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Components
import qs.Notifications
import "../../Notifications/model.js" as Model

// The popup toast stack (DESIGN.md §Notifications, M8b Task 5; sonner-style
// collapsed depth stack, M34 Task 2): a fixed pool of card slots
// (`poolRepeater` below, `_poolSize` deep) whose SAME Item instances get
// reassigned to different live notifications over time — never a
// Repeater bound straight to a reactively-recomputed array, which QML
// treats as a full model reset on every change and would restart every
// card's enter animation whenever any ONE notification arrived or left.
// Reusing fixed slots is what makes `Behavior on x`/`y` actually retarget
// smoothly (§4.4) instead of snapping, and what lets a departed entry keep
// its own Item alive (frozen at its last position) through its exit fade
// before the slot frees up — Panel.qml's "visible-until-opacity-0 hold"
// generalized to a pool instead of a single surface.
//
// Two geometries share the same pool, picked by `_expanded`
// (`_geomFor`/`_computeLayout` below): COLLAPSED is sonner's depth stack —
// the front card full-size, up to two older ones peeking a fixed sliver
// out from behind it, each SIZED narrower by an integer `Theme.space`
// step per level (owner amendment, 2026-08-18: never a fractional
// `transform: scale` — a 2px border under `scale(0.95)` rasterizes
// blurry) — critical always wins the front slot over a newer normal one
// (`Model.stackOrder`). EXPANDED is today's plain full-width list, one
// card per live popup, `panelGap` apart, ordered by `_entries` exactly as
// before this task. Hovering the stack (or `notifications expand
// on/off` over IPC, the rig's stand-in for a pointer this rig doesn't
// have — the bar chevron's own `expand` verb is the precedent) toggles
// between them, and pauses every visible popup's expiry for as long as
// it's expanded (the existing per-card `setPopupHovered`, applied
// stack-wide) — "hover shows all of the ones that appeared at once".
//
// Anchor corner is configurable (settings.json's `notifications.position`,
// M34 Task 1, default bottom-right) via Model.positionSpec — see
// `_positionSpec` below for how a single resolved object drives the
// PanelWindow's own anchors/margins, the stack's growth order and the
// enter/exit slide direction together.
//
// Suppressed entirely while the history center is open, whatever the
// configured corner (M34: one rule, no corner-collision math, since
// Center's own card is a fixed right-edge, full-height panel that overlaps
// every right-anchored toast position anyway and costs nothing to also
// suppress for the two left ones): a sticky critical popup (expiresAt = 0,
// never times out — see model.js's expire()) would otherwise sit
// permanently on top of the center's own card, both visually and for
// pointer input, since Toasts is on the Overlay layer above Center's Top
// layer. Hiding this surface for the duration costs nothing: the popup is
// still in NotificationService.popups, unaffected, and reappears the
// moment the center closes.
PanelWindow {
    id: root

    required property var modelData
    property var center: null
    screen: modelData

    // Bar.qml publishes its content-derived height as Theme.barHeight (the
    // same lookup Panel.qml uses) — the old hardcoded-32 mirror left toasts
    // overlapping the bar's bottom rows once the bar grew taller (same
    // stale literal Center.qml carried, fixed together in M13b Task 2).
    readonly property int _barHeight: Theme.barHeight

    // Resolves settings.json's notifications.position (default
    // bottom-right, M34 Task 1) to the anchors/margins/growth/slide-axis
    // this whole surface reads off below — see model.js's positionSpec()
    // for the corner math.
    readonly property var _positionSpec: Model.positionSpec(Config.get("notifications.position", Model.DEFAULT_POSITION))

    // Every live popup, grouped (Model.groupEntries), in whatever order
    // groupEntries itself returns (oldest-recent-activity-first) — the raw
    // truth `_syncDisplay` reconciles `_slots` against.
    readonly property var _groups: Model.groupEntries(NotificationService.popups)

    // Rank/expanded-order math below deliberately reads FROM `_slots`
    // (only ever written by `_syncDisplay`), never straight from `_groups`:
    // `_groups` updates the instant a notification disappears, so a
    // `_stackOrder`/`_entries` bound to it would already have forgotten a
    // departing entry by the time `_syncDisplay`'s own `on_GroupsChanged`
    // handler runs and tries to freeze its last position — it would read
    // back the post-removal fallback, not where the card actually was.
    // Reading `_slots` instead means the freeze snapshot, taken BEFORE
    // `_syncDisplay` writes the new `_slots` array, still sees the old
    // (pre-removal) layout.
    readonly property var _liveSlotEntries: root._slots
        .filter(function (s) { return s && !s.departing; })
        .map(function (s) { return s.entry; })
        .sort(function (a, b) { return a.arrivedAt - b.arrivedAt; })

    // Collapsed-stack front-to-back order (Model.stackOrder): index 0 is
    // the front card, 1/2 the two peek levels, the rest present only in
    // the count the expanded view reveals.
    readonly property var _stackOrder: Model.stackOrder(root._liveSlotEntries)

    // Expanded-view display order: newest nearest the anchor corner, same
    // as Task 1 — the Column-free layout below still needs this to decide
    // which end of the list is "closest to the anchor".
    readonly property var _entries: root._positionSpec.newestFirst
        ? root._liveSlotEntries.slice().reverse()
        : root._liveSlotEntries

    visible: (root._groups.length > 0 || root._hasDepartingSlots) && !(root.center && root.center.isOpen)
    color: "transparent"

    // Relative timestamps ("2m ago") only ever recompute off this timer per
    // the plan-wide constraint — never off the reducer's own 1s tick.
    property double _now: Date.now()
    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        onTriggered: root._now = Date.now()
    }

    WlrLayershell.namespace: "formalshell:notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: root._positionSpec.top
        bottom: root._positionSpec.bottom
        left: root._positionSpec.left
        right: root._positionSpec.right
    }
    margins {
        top: root._positionSpec.top ? root._barHeight + Theme.space.panelGap : 0
        bottom: root._positionSpec.bottom ? Theme.space.panelGap : 0
        left: root._positionSpec.left ? Theme.space.panelGap : 0
        right: root._positionSpec.right ? Theme.space.panelGap : 0
    }

    implicitWidth: stack.width
    implicitHeight: stack.height

    // --- the depth-stack pool -------------------------------------------

    // The inner NotificationCard is ALWAYS this width — never bound to
    // anything rank/mode-dependent. If it were, its own implicit height
    // (text reflow) would feed into `_layout` below (used for exactly
    // that: reading each card's natural height), which would then feed
    // back into this same card's width — a real binding loop, not just a
    // theoretical one. A collapsed peek level narrows visually instead:
    // `cardFrame` clips to the narrower rank width while `card` itself
    // stays put underneath at full width, `inset` (below) shifting it so
    // the SAME centered slice always shows through — the physical
    // equivalent of a viewport moving over a card that never resizes.
    readonly property real _cardWidth: Theme.space.popupWidthNarrow
    // The outer frame's width, front/expanded alike — matches the
    // pre-M34 `card.width + Theme.borderWidth` shape (the left rule's own
    // reserve; Cell already draws its own bottom/right rule).
    readonly property real _frameWidth: root._cardWidth + Theme.borderWidth
    readonly property int _maxPeekLevels: 2
    readonly property real _peekInset: Theme.space.lg
    readonly property real _peekOffset: Theme.space.sm

    // MAX_POPUPS (model.js) caps live groups at 4; a dismiss-everything
    // moment can put all 4 into flight departing at once while 4 fresh
    // ones are already arriving, so 8 slots covers the worst realistic
    // case with headroom. A pool this small existing purely to dodge
    // Repeater's array-reset behavior (see header) never needs to be
    // config-driven.
    readonly property int _poolSize: 8
    // Pre-filled with `_poolSize` nulls up front — `_syncDisplay`'s "first
    // empty slot" search below walks existing INDICES, so a `_slots`
    // starting at length 0 never has an index to claim and every arrival
    // is silently dropped.
    property var _slots: new Array(root._poolSize).fill(null)

    readonly property bool _hasDepartingSlots: root._slots.some(function (s) { return s && s.departing; })

    readonly property var _fallbackGeom: ({ x: 0, y: 0, width: root._frameWidth, inset: 0, z: 0, contentVisible: false })

    readonly property var _emptyEntry: ({
        id: "", appName: "", appIcon: "", summary: "", body: "", urgency: 1,
        actions: [], image: "", local: false, arrivedAt: 0, seenAt: null,
        expiresAt: null, memberIds: []
    })

    function _slotIndexForKey(key) {
        for (var i = 0; i < root._slots.length; i++) {
            if (root._slots[i] && root._slots[i].key === key)
                return i;
        }
        return -1;
    }

    // Reconciles `_slots` against the live truth (`_groups`) whenever it
    // changes: an occupant still live gets its entry refreshed in place: a
    // slot's group can change identity mid-life if its representative
    // (newest member) changes; a slot whose group disappeared is marked
    // departing and has its CURRENT geometry frozen (via `_geomFor`, read
    // before this function ever touches `_slots`) so its exit fade starts
    // from wherever it actually was, mid-reflow included; a genuinely new
    // group claims the first empty slot.
    function _syncDisplay() {
        var liveByKey = {};
        root._groups.forEach(function (g) { liveByKey[Model.groupKey(g)] = g; });

        var slots = root._slots.slice();
        var occupied = {};

        for (var i = 0; i < slots.length; i++) {
            var s = slots[i];
            if (!s)
                continue;
            var g = liveByKey[s.key];
            if (g) {
                slots[i] = { key: s.key, entry: g, departing: false, frozen: null };
                occupied[s.key] = true;
            } else if (!s.departing) {
                slots[i] = { key: s.key, entry: s.entry, departing: true, frozen: root._geomFor(i) };
                occupied[s.key] = true;
            } else {
                occupied[s.key] = true;
            }
        }

        root._groups.forEach(function (g) {
            var key = Model.groupKey(g);
            if (occupied[key])
                return;
            for (var j = 0; j < slots.length; j++) {
                if (!slots[j]) {
                    slots[j] = { key: key, entry: g, departing: false, frozen: null };
                    occupied[key] = true;
                    return;
                }
            }
        });

        root._slots = slots;
    }

    function _clearSlot(index) {
        var slots = root._slots.slice();
        slots[index] = null;
        root._slots = slots;
    }

    on_GroupsChanged: root._syncDisplay()
    Component.onCompleted: root._syncDisplay()

    // Per-slot target geometry for both modes, keyed by pool index —
    // `x`/`y`/`width`/`z` only; height is deliberately NOT included here:
    // it stays each card's own natural implicit height in both modes, so
    // reading it back (`poolRepeater.itemAt(i).height` below) never closes
    // a binding loop against this same computation.
    readonly property var _layout: root._computeLayout()

    function _computeLayout() {
        var out = {};
        var spec = root._positionSpec;

        var frontIdx = root._stackOrder.length > 0 ? root._slotIndexForKey(Model.groupKey(root._stackOrder[0])) : -1;
        var frontItem = frontIdx >= 0 ? poolRepeater.itemAt(frontIdx) : null;
        var frontHeight = frontItem ? frontItem.height : 0;

        for (var r = 0; r < root._stackOrder.length; r++) {
            var idx = root._slotIndexForKey(Model.groupKey(root._stackOrder[r]));
            if (idx < 0)
                continue;
            var clamped = Math.min(r, root._maxPeekLevels);
            var ins = clamped * root._peekInset;
            var cx = ins;
            // The reveal recedes AWAY from the anchor edge, same as
            // sonner's own translateY: the anchor edge already carries the
            // front card flush against it (panelGap margin), so a peek can
            // only sit further from that edge, its top-`peekOffset` (top
            // anchor) or bottom-`peekOffset` (bottom anchor) sliver poking
            // out from behind whichever card is in front of it.
            var cy = spec.top ? clamped * root._peekOffset : (root._maxPeekLevels - clamped) * root._peekOffset;
            var cw = root._frameWidth - ins * 2;
            out[idx] = { collapsed: { x: cx, y: cy, width: cw, inset: ins, z: root._stackOrder.length - r, contentVisible: r === 0 } };
        }

        var y = 0;
        for (var i = 0; i < root._entries.length; i++) {
            var eidx = root._slotIndexForKey(Model.groupKey(root._entries[i]));
            if (eidx < 0)
                continue;
            if (!out[eidx])
                out[eidx] = {};
            out[eidx].expanded = { x: 0, y: y, width: root._frameWidth, inset: 0, z: root._entries.length - i, contentVisible: true };
            var eitem = poolRepeater.itemAt(eidx);
            var eh = eitem ? eitem.height : 0;
            y += eh + Theme.space.panelGap;
        }

        out._collapsedTotalHeight = frontHeight + root._maxPeekLevels * root._peekOffset;
        out._expandedTotalHeight = root._entries.length > 0 ? Math.max(0, y - Theme.space.panelGap) : 0;
        return out;
    }

    function _geomFor(index) {
        var slot = root._slots[index];
        if (!slot)
            return root._fallbackGeom;
        if (slot.departing)
            return slot.frozen || root._fallbackGeom;
        var entry = root._layout[index];
        if (!entry)
            return root._fallbackGeom;
        return root._expanded ? entry.expanded : entry.collapsed;
    }

    // A departing card keeps whatever bounds it had when it left, and the
    // window itself must stay at least that tall until the fade finishes —
    // otherwise dismissing the last live popup would shrink the window to
    // its new (empty) target height instantly and clip the exit mid-fade.
    function _departingExtent() {
        var maxY = 0;
        for (var i = 0; i < root._slots.length; i++) {
            var s = root._slots[i];
            if (s && s.departing && s.frozen) {
                var item = poolRepeater.itemAt(i);
                var h = item ? item.height : 0;
                maxY = Math.max(maxY, s.frozen.y + h);
            }
        }
        return maxY;
    }

    readonly property real _targetHeight: Math.max(
        root._expanded ? (root._layout._expandedTotalHeight || 0) : (root._layout._collapsedTotalHeight || 0),
        root._departingExtent())

    // --- hover / IPC expand ----------------------------------------------

    // NotificationService.stackExpanded is the IPC-driven force flag only
    // (`notifications expand on|off`); local hover ORs in independently so
    // two screens' own stacks never fight over one shared boolean.
    readonly property bool _expanded: stackHover.hovered || NotificationService.stackExpanded

    readonly property var _visibleMemberIds: {
        var ids = [];
        root._groups.forEach(function (g) { (g.memberIds || [g.id]).forEach(function (id) { ids.push(id); }); });
        return ids;
    }
    property var _prevPausedIds: []

    function _syncExpandPause() {
        var want = root._expanded ? root._visibleMemberIds : [];
        root._prevPausedIds.forEach(function (id) {
            if (want.indexOf(id) < 0)
                NotificationService.setPopupHovered([id], false);
        });
        if (want.length > 0)
            NotificationService.setPopupHovered(want, true);
        root._prevPausedIds = want;
    }

    on_ExpandedChanged: root._syncExpandPause()
    on_VisibleMemberIdsChanged: root._syncExpandPause()

    Item {
        id: stack
        width: root._frameWidth
        height: root._targetHeight

        // The layer surface itself is sized off this height (implicitHeight
        // above), and the compositor's resize is a real round trip — with
        // no Behavior here the window used to jump to its target size in
        // one frame while the delegates' own x/y Behaviors were still
        // gliding, so a card mid-glide would render clipped to whichever
        // (old or new) buffer size won the race. Matching duration/easing
        // to the delegate Behaviors below keeps the surface resize and the
        // card layout in lockstep frame by frame.
        Behavior on height {
            NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
        }

        // Hover anywhere on the stack expands it (DESIGN.md §Notifications):
        // a HoverHandler, not a MouseArea, so it keeps reporting hover
        // across the whole bounding box even with the cards' own
        // MouseAreas layered on top of it.
        HoverHandler {
            id: stackHover
        }

        Repeater {
            id: poolRepeater
            model: root._poolSize

            delegate: Item {
                id: cardFrame
                required property int index

                readonly property var _slot: root._slots[cardFrame.index]
                readonly property var _geom: root._geomFor(cardFrame.index)

                visible: cardFrame._slot !== null
                x: cardFrame._geom.x
                y: cardFrame._geom.y
                z: cardFrame._geom.z
                width: cardFrame._geom.width
                implicitHeight: card.height + Theme.borderWidth
                height: implicitHeight
                // A peek level clips down to its narrower rank width; the
                // card underneath keeps its own fixed full width and just
                // shifts by `inset` (below) so the same centered slice
                // shows through, sonner's "sized narrower... horizontally
                // centered" read entirely as a viewport, never a resize of
                // the card itself.
                clip: true

                Behavior on x {
                    NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
                }
                Behavior on y {
                    NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
                }

                // presence: 0 = off-stack, 1 = fully shown — one scalar
                // drives both the enter (freshly assigned slot) and exit
                // (departing) fade, so the exact same Behavior retargets
                // whichever direction is live at any moment (DESIGN.md
                // §4.4). A newly-created Item's very first value never
                // animates (Behaviors only fire on later changes), which is
                // exactly wanted: a slot claimed as the new front card
                // simply starts its 0->1 climb from nothing, at its
                // already-correct target x/y.
                property real presence: (cardFrame._slot && !cardFrame._slot.departing) ? 1 : 0
                Behavior on presence {
                    NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
                }
                opacity: cardFrame.presence
                // Enter/exit slide (DESIGN.md §4.2): toward/from the
                // anchored side edge, same slideSign Task 1 already
                // resolves for the enter direction.
                transform: Translate { x: (1 - cardFrame.presence) * Theme.motion.slide * root._positionSpec.slideSign }

                onPresenceChanged: {
                    if (cardFrame.presence === 0 && cardFrame._slot && cardFrame._slot.departing)
                        root._clearSlot(cardFrame.index);
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.color.background
                }
                Rectangle {
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

                NotificationCard {
                    id: card
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.topMargin: Theme.borderWidth
                    // Shifts LEFT (negative once inset > 0) so cardFrame's
                    // clip removes `inset` px from each side of this fixed-
                    // width card — see the clip note on cardFrame above.
                    anchors.leftMargin: Theme.borderWidth - cardFrame._geom.inset

                    entry: cardFrame._slot ? cardFrame._slot.entry : root._emptyEntry
                    now: root._now
                    compact: true
                    width: root._cardWidth
                    contentVisible: cardFrame._geom.contentVisible

                    // Gated on !root._expanded: `stackHover`'s HoverHandler
                    // covers this same card's whole bounding box, so a card
                    // hover inside an already-expanded stack always
                    // coincides with `root._expanded` staying true — letting
                    // this fire there too raced `_syncExpandPause`'s
                    // stack-wide pause (moving the pointer from card A to
                    // card B cleared A's id from `_hoveredPopups` with
                    // neither `_expandedChanged` nor `_visibleMemberIdsChanged`
                    // firing to restore it, so A could expire mid-hover).
                    // Un-expanded, only the front card is interactive, and
                    // this stays its per-card pause.
                    onHoveredChanged: {
                        if (cardFrame._slot && !root._expanded)
                            NotificationService.setPopupHovered(cardFrame._slot.entry.memberIds, card.hovered);
                    }
                    onDismiss: {
                        if (cardFrame._slot)
                            NotificationService.dismissPopupGroup(cardFrame._slot.entry.memberIds);
                    }
                    onBodyClicked: {
                        if (!cardFrame._slot)
                            return;
                        var entry = cardFrame._slot.entry;
                        if (entry.actions.some(a => a.key === "default"))
                            NotificationService.invokeAction(entry.id, "default");
                        else
                            NotificationService.focusSender(entry.id);
                    }
                    onActionInvoked: key => {
                        if (cardFrame._slot)
                            NotificationService.invokeAction(cardFrame._slot.entry.id, key);
                    }
                }

                // Dog-ear fold mark (DESIGN.md §2 item 7) — each toast is
                // its own small card, so each gets its own mark, peek
                // levels included: they're real cards, just with their
                // content hidden.
                DogEar {}
            }
        }
    }
}

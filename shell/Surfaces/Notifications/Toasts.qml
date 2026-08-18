import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Components
import qs.Notifications
import "../../Notifications/model.js" as Model

// The popup toast stack (DESIGN.md §Notifications, M8b Task 5): a Column of
// independent omarchy-style cards — "each popup toast is its own small
// omarchy card... stacked toasts keep omarchy's card-to-card gap, not fused
// adjacency" — so every card below gets its own full border (a small
// per-card frame drawing the top/left rule, NotificationCard's own Cell
// contract closing the bottom/right) with `Theme.space.panelGap` of
// daylight between cards, replacing the old single shared-frame/
// zero-spacing ledger stack. Passive overlay — no keyboard focus,
// click-through everywhere but the cards themselves (PanelWindow already
// only occupies the frame's own bounds, so nothing extra is needed there).
// One instance per screen, wired in shell.qml the same way as Bar/Background.
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

    // Identical repeats collapse into one card carrying the group's count
    // (Model.groupEntries): each row is a copy of the group's newest member,
    // so `id`/`actions` still target the notification a click should act on,
    // while `memberIds` is what hover-pause and dismiss operate over.
    // groupEntries always returns oldest-first; the Column below lays
    // children out top-down unconditionally regardless of which corner the
    // window itself anchors to (its content area is sized to exactly the
    // column's own bounds, so there's no slack for a top/left-vs-bottom/
    // right internal anchor to matter) — so putting the newest card nearest
    // the anchor point is purely a matter of which end of this list it's on.
    readonly property var _entries: root._positionSpec.newestFirst
        ? Model.groupEntries(NotificationService.popups).slice().reverse()
        : Model.groupEntries(NotificationService.popups)
    visible: root._entries.length > 0 && !(root.center && root.center.isOpen)
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

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    Column {
        id: column
        anchors.top: parent.top
        anchors.left: parent.left
        spacing: Theme.space.panelGap

        Repeater {
            model: root._entries

            delegate: Item {
                id: cardFrame
                required property var modelData

                implicitWidth: card.width + Theme.borderWidth
                implicitHeight: card.height + Theme.borderWidth
                width: implicitWidth
                height: implicitHeight

                // Enter (DESIGN.md §4.2): each new toast fades in and slides
                // from the anchored side edge — slideSign flips the
                // direction for a left-anchored stack — one animated scalar.
                // Removal stays instant — the Repeater destroys the delegate
                // with its model row, and a dismissal should feel immediate
                // anyway.
                property real enter: 1
                opacity: cardFrame.enter
                transform: Translate { x: (1 - cardFrame.enter) * Theme.motion.slide * root._positionSpec.slideSign }

                NumberAnimation on enter {
                    from: 0
                    to: 1
                    duration: Theme.motion.standard
                    easing.type: Theme.motion.easing
                }

                // Opaque card backing plus its own top/left rule — unlike
                // the old shared frame, every toast now closes its own ring
                // (NotificationCard's Cell contract draws the bottom/right
                // half), so it reads as a genuine floating card even where
                // the desktop behind it isn't a flat color.
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
                    anchors.leftMargin: Theme.borderWidth

                    entry: cardFrame.modelData
                    now: root._now

                    // Pause-on-hover (DESIGN.md §Notifications, M15 Task 2):
                    // NotificationService's own 1s expiry timer reads this
                    // back to hold the popup's countdown while the pointer
                    // is over it. Every member's countdown is held, not just
                    // the representative's, or a hovered group would shrink
                    // under the pointer.
                    onHoveredChanged: NotificationService.setPopupHovered(cardFrame.modelData.memberIds, card.hovered)

                    onDismiss: NotificationService.dismissPopupGroup(cardFrame.modelData.memberIds)
                    onBodyClicked: {
                        if (cardFrame.modelData.actions.some(a => a.key === "default"))
                            NotificationService.invokeAction(cardFrame.modelData.id, "default");
                        else
                            NotificationService.focusSender(cardFrame.modelData.id);
                    }
                    onActionInvoked: key => NotificationService.invokeAction(cardFrame.modelData.id, key)
                }

                // Dog-ear fold mark (DESIGN.md §2 item 7) — each toast is
                // its own small card, so each gets its own mark.
                DogEar {}
            }
        }
    }
}
